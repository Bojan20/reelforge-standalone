//! FAZA 5.1.8 — Auto-compliance validator for generated audio.
//!
//! Every `GenerationResponse` carries a `ComplianceReport` so downstream
//! callers (UI badge, `rf-slot-builder` validator, audit pipeline, future
//! AudioSeal watermarker in 5.2.4) never have to *re-scan* the PCM. The
//! report is computed once at the backend boundary in O(N) and travels
//! attached to the PCM through every serialization layer (FFI metadata
//! JSON, Dart `GenerationResult.metadata.compliance`).
//!
//! ## Scope of checks
//!
//! Two tiers:
//! 1. **Hard invariants** — `Fail` if violated. These are integrity gates:
//!    NaN/Inf, clipping above headroom, sample-rate / channel mismatch
//!    against the request, frame-count mismatch with declared duration,
//!    truly empty PCM, all-silence.
//! 2. **Production quality** — `Warn` if outside best-practice range.
//!    These are advisory: peak too hot (>= -1 dBFS), peak too low
//!    (< -30 dBFS), DC offset (|mean| > 0.01), silence ratio (> 90 %),
//!    short clip (< 100 ms — likely a request bug).
//!
//! Jurisdictional LUFS limits (UKGC -23 LUFS lobby, MGA -16 LUFS peak)
//! are intentionally **not** enforced here — full BS.1770 K-weighting +
//! gated integration belongs in `rf-slot-builder`'s mastering pipeline
//! (5.2.4 AudioSeal stack), and we only carry an LKFS *estimate* (peak
//! RMS) so the UI badge can hint without bluffing.
//!
//! ## Determinism
//!
//! All checks are pure functions of `(response, request)`. Same input ⇒
//! byte-identical report. This is part of the seed contract — the
//! variation panel relies on it so two clicks with identical inputs
//! always paint the same compliance badge.

use crate::request::GenerationRequest;
use crate::response::GenerationResponse;
use serde::{Deserialize, Serialize};

// ───────────────────────────── Constants ─────────────────────────────

/// Anything `|s|` above this is counted as a clipped sample. Backends
/// MUST stay under 1.0 strictly; the tiny epsilon catches naive rounding.
const CLIP_THRESHOLD: f32 = 0.999;

/// Below this absolute amplitude a sample is "silent" for ratio counting.
const SILENCE_AMP: f32 = 1e-4;

/// Headroom band (in dBFS). Outside ⇒ `Warn`.
const PEAK_TOO_HOT_DBFS: f32 = -1.0;
const PEAK_TOO_LOW_DBFS: f32 = -30.0;

/// DC offset that triggers a warn (absolute mean). Real generative audio
/// should average to zero; > 0.01 means a bias is leaking through.
const DC_OFFSET_WARN: f32 = 0.01;

/// Silence-ratio warn threshold (fraction of frames below `SILENCE_AMP`).
const SILENCE_RATIO_WARN: f32 = 0.90;

/// Minimum sensible clip duration before we flag "request bug".
const MIN_SENSIBLE_DURATION_SECONDS: f32 = 0.1;

/// Tolerance for declared-duration vs. actual frame count, in frames.
/// Backends round when computing `(duration * sample_rate)`; one frame
/// off either way is fine.
const FRAME_COUNT_TOLERANCE: isize = 2;

// ───────────────────────────── Types ─────────────────────────────────

/// Outcome of a single check. Ordered so `Fail > Warn > Pass`, used to
/// aggregate the report-level status with `max`.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
)]
#[serde(rename_all = "snake_case")]
pub enum ComplianceLevel {
    Pass,
    Warn,
    Fail,
}

impl ComplianceLevel {
    pub fn label(self) -> &'static str {
        match self {
            Self::Pass => "PASS",
            Self::Warn => "WARN",
            Self::Fail => "FAIL",
        }
    }
}

/// Single finding inside a report. `id` is a stable kebab-case key so the
/// UI can localize / filter without string-matching the message.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ComplianceFinding {
    pub id: String,
    pub level: ComplianceLevel,
    pub message: String,
    /// Optional numeric payload — UI / audit pipelines display it raw.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<f32>,
}

impl ComplianceFinding {
    fn pass(id: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            level: ComplianceLevel::Pass,
            message: message.into(),
            value: None,
        }
    }
    fn warn(id: impl Into<String>, message: impl Into<String>, value: Option<f32>) -> Self {
        Self {
            id: id.into(),
            level: ComplianceLevel::Warn,
            message: message.into(),
            value,
        }
    }
    fn fail(id: impl Into<String>, message: impl Into<String>, value: Option<f32>) -> Self {
        Self {
            id: id.into(),
            level: ComplianceLevel::Fail,
            message: message.into(),
            value,
        }
    }
}

/// Complete compliance manifest attached to every `GenerationResponse`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ComplianceReport {
    /// Aggregate worst-case level across all findings.
    pub level: ComplianceLevel,
    /// Findings, in evaluation order. Hard-fail checks come first so the
    /// UI can render "FAIL: NaN sample at index 4823" without scrolling.
    pub findings: Vec<ComplianceFinding>,
    /// Peak absolute sample, dBFS. `-inf` for all-silence buffers.
    pub peak_dbfs: f32,
    /// Full-clip RMS, dBFS. Coarse loudness proxy until BS.1770 ships.
    pub rms_dbfs: f32,
    /// DC offset (mean sample). Should be ≈ 0 for clean audio.
    pub dc_offset: f32,
    /// Number of samples flagged as clipping.
    pub clip_count: u32,
    /// Number of non-finite samples (NaN / Inf).
    pub nan_count: u32,
    /// Fraction of frames whose `|amp|` < `SILENCE_AMP`. Range `[0, 1]`.
    pub silence_ratio: f32,
    /// Actual duration in seconds (derived from PCM length / sample rate).
    pub duration_seconds: f32,
}

impl ComplianceReport {
    pub fn is_pass(&self) -> bool {
        self.level == ComplianceLevel::Pass
    }
    pub fn is_fail(&self) -> bool {
        self.level == ComplianceLevel::Fail
    }

    /// Stub report used when deserializing a `GenerationResponse` that
    /// predates 5.1.8 (no `compliance` field). The UI renders this as
    /// "unknown" rather than treating the absence as silent pass.
    pub fn default_unknown() -> Self {
        Self {
            level: ComplianceLevel::Warn,
            findings: vec![ComplianceFinding {
                id: "no-report".into(),
                level: ComplianceLevel::Warn,
                message: "Response was produced before compliance manifests \
                          existed; no checks were run."
                    .into(),
                value: None,
            }],
            peak_dbfs: f32::NEG_INFINITY,
            rms_dbfs: f32::NEG_INFINITY,
            dc_offset: 0.0,
            clip_count: 0,
            nan_count: 0,
            silence_ratio: 0.0,
            duration_seconds: 0.0,
        }
    }
}

// ───────────────────────────── Compute ───────────────────────────────

/// Compute the full report for a freshly produced response.
///
/// Pure function — no allocations beyond the finding list, no mutation
/// of inputs, no I/O. Safe to call from `MockBackend::generate` and from
/// the future ONNX backend.
pub fn compute_compliance(
    response: &GenerationResponse,
    request: &GenerationRequest,
) -> ComplianceReport {
    let mut findings = Vec::<ComplianceFinding>::with_capacity(8);

    // ── Structural integrity ──────────────────────────────────────────
    if response.pcm.is_empty() {
        // Nothing else to compute — short-circuit with a single Fail.
        findings.push(ComplianceFinding::fail(
            "empty-pcm",
            "Response PCM is empty",
            Some(0.0),
        ));
        return ComplianceReport {
            level: ComplianceLevel::Fail,
            findings,
            peak_dbfs: f32::NEG_INFINITY,
            rms_dbfs: f32::NEG_INFINITY,
            dc_offset: 0.0,
            clip_count: 0,
            nan_count: 0,
            silence_ratio: 1.0,
            duration_seconds: 0.0,
        };
    }

    if !matches!(response.channels, 1 | 2) {
        findings.push(ComplianceFinding::fail(
            "bad-channel-count",
            format!(
                "Response channels = {} (must be 1 or 2)",
                response.channels
            ),
            Some(response.channels as f32),
        ));
    }

    // ── Sample-level scan ─────────────────────────────────────────────
    let mut nan_count: u32 = 0;
    let mut clip_count: u32 = 0;
    let mut peak: f32 = 0.0;
    let mut sum: f64 = 0.0;
    let mut sum_sq: f64 = 0.0;
    let mut silence: u32 = 0;
    let n = response.pcm.len();

    for &s in &response.pcm {
        if !s.is_finite() {
            nan_count += 1;
            continue;
        }
        let abs = s.abs();
        if abs > peak {
            peak = abs;
        }
        if abs >= CLIP_THRESHOLD {
            clip_count += 1;
        }
        if abs < SILENCE_AMP {
            silence += 1;
        }
        sum += s as f64;
        sum_sq += (s as f64) * (s as f64);
    }
    let finite_n = (n as u32).saturating_sub(nan_count) as f64;
    let dc_offset = if finite_n > 0.0 {
        (sum / finite_n) as f32
    } else {
        0.0
    };
    let rms = if finite_n > 0.0 {
        (sum_sq / finite_n).sqrt() as f32
    } else {
        0.0
    };
    let peak_dbfs = amp_to_dbfs(peak);
    let rms_dbfs = amp_to_dbfs(rms);
    let silence_ratio = if n > 0 {
        silence as f32 / n as f32
    } else {
        1.0
    };

    if nan_count > 0 {
        findings.push(ComplianceFinding::fail(
            "non-finite-samples",
            format!("{nan_count} non-finite samples (NaN/Inf)"),
            Some(nan_count as f32),
        ));
    }
    if clip_count > 0 {
        findings.push(ComplianceFinding::fail(
            "clipping",
            format!("{clip_count} clipped samples (|s| ≥ {CLIP_THRESHOLD})"),
            Some(clip_count as f32),
        ));
    }
    if silence_ratio >= 1.0 {
        // All-silence is *Fail*, not Warn: nothing was generated.
        findings.push(ComplianceFinding::fail(
            "all-silence",
            "PCM contains no audible signal (all samples below 1e-4)",
            Some(silence_ratio),
        ));
    } else if silence_ratio > SILENCE_RATIO_WARN {
        findings.push(ComplianceFinding::warn(
            "mostly-silent",
            format!(
                "{:.0}% of frames are silent (threshold {:.0}%)",
                silence_ratio * 100.0,
                SILENCE_RATIO_WARN * 100.0
            ),
            Some(silence_ratio),
        ));
    }

    // ── Quality warnings (peak band) ──────────────────────────────────
    if peak_dbfs.is_finite() && peak_dbfs > PEAK_TOO_HOT_DBFS {
        findings.push(ComplianceFinding::warn(
            "peak-too-hot",
            format!(
                "Peak {peak_dbfs:.2} dBFS exceeds headroom band (> {PEAK_TOO_HOT_DBFS:.0} dBFS)"
            ),
            Some(peak_dbfs),
        ));
    }
    if peak_dbfs.is_finite() && peak_dbfs < PEAK_TOO_LOW_DBFS && silence_ratio < 1.0 {
        findings.push(ComplianceFinding::warn(
            "peak-too-low",
            format!(
                "Peak {peak_dbfs:.2} dBFS below practical floor (< {PEAK_TOO_LOW_DBFS:.0} dBFS)"
            ),
            Some(peak_dbfs),
        ));
    }
    if dc_offset.abs() > DC_OFFSET_WARN {
        findings.push(ComplianceFinding::warn(
            "dc-offset",
            format!("DC offset {dc_offset:.4} exceeds {DC_OFFSET_WARN:.4}"),
            Some(dc_offset),
        ));
    }

    // ── Sample-rate / channel / frame-count vs. request ───────────────
    let requested_sr = if request.sample_rate_hz == 0 {
        crate::NATIVE_SAMPLE_RATE
    } else {
        request.sample_rate_hz
    };
    if response.sample_rate_hz != requested_sr {
        findings.push(ComplianceFinding::fail(
            "sample-rate-mismatch",
            format!(
                "Response sample rate {} ≠ requested {} Hz",
                response.sample_rate_hz, requested_sr
            ),
            Some(response.sample_rate_hz as f32),
        ));
    }
    let actual_duration = response.duration_seconds();
    if actual_duration < MIN_SENSIBLE_DURATION_SECONDS {
        findings.push(ComplianceFinding::warn(
            "very-short-clip",
            format!(
                "Clip duration {actual_duration:.3}s below sensible minimum {MIN_SENSIBLE_DURATION_SECONDS:.2}s"
            ),
            Some(actual_duration),
        ));
    }
    let expected_frames =
        (request.duration_seconds * requested_sr as f32).round() as isize;
    let actual_frames = response.frame_count() as isize;
    if (actual_frames - expected_frames).abs() > FRAME_COUNT_TOLERANCE {
        findings.push(ComplianceFinding::fail(
            "frame-count-mismatch",
            format!(
                "Response frames {actual_frames} ≠ expected {expected_frames} (tolerance ±{FRAME_COUNT_TOLERANCE})"
            ),
            Some(actual_frames as f32),
        ));
    }

    // If we got here with no findings, the clip is clean.
    if findings.is_empty() {
        findings.push(ComplianceFinding::pass(
            "clean",
            "All compliance checks passed",
        ));
    }

    let level = findings
        .iter()
        .map(|f| f.level)
        .max()
        .unwrap_or(ComplianceLevel::Pass);

    ComplianceReport {
        level,
        findings,
        peak_dbfs,
        rms_dbfs,
        dc_offset,
        clip_count,
        nan_count,
        silence_ratio,
        duration_seconds: actual_duration,
    }
}

// ───────────────────────────── Helpers ───────────────────────────────

/// Convert a linear amplitude `[0, +∞)` to dBFS. Zero (or near-zero)
/// returns `-inf` — let the UI render that as "−∞ dB" or a dash. Use
/// `f32::NEG_INFINITY` rather than a sentinel float so serde encodes it
/// as `-Infinity` and the Dart side can detect with `isFinite()`.
fn amp_to_dbfs(amp: f32) -> f32 {
    if amp <= 0.0 || !amp.is_finite() {
        return f32::NEG_INFINITY;
    }
    20.0 * amp.log10()
}

// ───────────────────────────── Tests ─────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::request::{GenerationRequest, GenerationStyle};
    use crate::response::{GenerationResponse, ProvenanceTag};

    fn req(duration: f32) -> GenerationRequest {
        GenerationRequest {
            prompt: "p".into(),
            duration_seconds: duration,
            sample_rate_hz: 0,
            seed: Some(1),
            style: GenerationStyle::default(),
        }
    }

    fn make_response(pcm: Vec<f32>, sr: u32, ch: u16) -> GenerationResponse {
        GenerationResponse {
            pcm,
            sample_rate_hz: sr,
            channels: ch,
            latency_ms: 1,
            provenance: ProvenanceTag {
                backend_id: "test".into(),
                model_id: "none".into(),
                seed: Some(1),
                generated_at_utc: "2026-05-11T00:00:00Z".into(),
            },
            // Stub — populated by compute_compliance in production. Tests
            // overwrite as needed.
            compliance: ComplianceReport::default_unknown(),
        }
    }

    #[test]
    fn clean_clip_is_pass() {
        // 0.2s of -6 dBFS sine at 1 kHz, stereo.
        let sr = 48_000u32;
        let frames = (0.2 * sr as f32) as usize;
        let mut pcm = Vec::with_capacity(frames * 2);
        for i in 0..frames {
            let s = (i as f32 * 2.0 * std::f32::consts::PI * 1000.0 / sr as f32).sin() * 0.5;
            pcm.push(s);
            pcm.push(s);
        }
        let res = make_response(pcm, sr, 2);
        let report = compute_compliance(&res, &req(0.2));
        assert_eq!(report.level, ComplianceLevel::Pass, "{report:?}");
        assert!(report.findings.iter().any(|f| f.id == "clean"));
        assert!(report.peak_dbfs < 0.0 && report.peak_dbfs > -10.0);
        assert!(report.dc_offset.abs() < 0.01);
        assert_eq!(report.clip_count, 0);
        assert_eq!(report.nan_count, 0);
    }

    #[test]
    fn nan_sample_is_hard_fail() {
        let mut pcm = vec![0.2_f32; 200];
        pcm[42] = f32::NAN;
        let res = make_response(pcm, 48_000, 2);
        let report = compute_compliance(&res, &req(200.0 / 48_000.0 / 2.0));
        assert_eq!(report.level, ComplianceLevel::Fail);
        assert!(report.findings.iter().any(|f| f.id == "non-finite-samples"));
        assert_eq!(report.nan_count, 1);
    }

    #[test]
    fn clipping_is_hard_fail() {
        let pcm = vec![0.999_5_f32; 200];
        let res = make_response(pcm, 48_000, 2);
        let report = compute_compliance(&res, &req(200.0 / 48_000.0 / 2.0));
        assert_eq!(report.level, ComplianceLevel::Fail);
        assert!(report.findings.iter().any(|f| f.id == "clipping"));
        assert!(report.clip_count >= 200);
    }

    #[test]
    fn all_silence_is_hard_fail() {
        let pcm = vec![0.0_f32; 4_800];
        let res = make_response(pcm, 48_000, 2);
        let report = compute_compliance(&res, &req(0.05));
        assert_eq!(report.level, ComplianceLevel::Fail);
        assert!(report.findings.iter().any(|f| f.id == "all-silence"));
        assert!((report.silence_ratio - 1.0).abs() < 1e-6);
    }

    #[test]
    fn dc_offset_is_warn() {
        // Constant non-zero signal — heavy DC bias.
        let pcm = vec![0.3_f32; 4_800];
        let res = make_response(pcm, 48_000, 2);
        let report = compute_compliance(&res, &req(0.05));
        assert_eq!(report.level, ComplianceLevel::Warn);
        assert!(report.findings.iter().any(|f| f.id == "dc-offset"));
        // Constant 0.3 → peak hot at -10 dBFS is fine, but dc dominates.
    }

    #[test]
    fn peak_too_hot_is_warn() {
        // Sine at 0.95 amp — peak ≈ -0.45 dBFS, hotter than -1 threshold.
        let sr = 48_000u32;
        let frames = (0.2 * sr as f32) as usize;
        let mut pcm = Vec::with_capacity(frames * 2);
        for i in 0..frames {
            let s = (i as f32 * 2.0 * std::f32::consts::PI * 440.0 / sr as f32).sin() * 0.95;
            pcm.push(s);
            pcm.push(s);
        }
        let res = make_response(pcm, sr, 2);
        let report = compute_compliance(&res, &req(0.2));
        assert_eq!(report.level, ComplianceLevel::Warn, "{report:?}");
        assert!(report.findings.iter().any(|f| f.id == "peak-too-hot"));
    }

    #[test]
    fn empty_pcm_short_circuits_to_fail() {
        let res = make_response(vec![], 48_000, 2);
        let report = compute_compliance(&res, &req(0.5));
        assert_eq!(report.level, ComplianceLevel::Fail);
        assert_eq!(report.findings.len(), 1);
        assert_eq!(report.findings[0].id, "empty-pcm");
        assert!(report.peak_dbfs.is_infinite() && report.peak_dbfs.is_sign_negative());
    }

    #[test]
    fn frame_count_mismatch_fails() {
        // 0.5s requested at 48 kHz stereo → 48_000 frames expected.
        // We give 47_000.
        let pcm = vec![0.1_f32; 47_000 * 2];
        let res = make_response(pcm, 48_000, 2);
        let report = compute_compliance(&res, &req(0.5));
        assert_eq!(report.level, ComplianceLevel::Fail);
        assert!(report
            .findings
            .iter()
            .any(|f| f.id == "frame-count-mismatch"));
    }

    #[test]
    fn level_ordering_fail_dominates_warn() {
        assert!(ComplianceLevel::Fail > ComplianceLevel::Warn);
        assert!(ComplianceLevel::Warn > ComplianceLevel::Pass);
    }

    #[test]
    fn report_is_byte_identical_for_identical_input() {
        let pcm: Vec<f32> = (0..9600).map(|i| (i as f32 * 0.001).sin() * 0.4).collect();
        let res1 = make_response(pcm.clone(), 48_000, 2);
        let res2 = make_response(pcm, 48_000, 2);
        let r1 = compute_compliance(&res1, &req(0.1));
        let r2 = compute_compliance(&res2, &req(0.1));
        // Determinism contract for the variation panel.
        assert_eq!(r1, r2);
    }

    #[test]
    fn amp_to_dbfs_known_values() {
        // 1.0 → 0 dBFS
        assert!((amp_to_dbfs(1.0) - 0.0).abs() < 1e-4);
        // 0.5 → -6.02 dBFS
        assert!((amp_to_dbfs(0.5) - (-6.0206)).abs() < 1e-3);
        // 0.0 → -inf
        assert!(amp_to_dbfs(0.0).is_infinite());
        assert!(amp_to_dbfs(0.0).is_sign_negative());
    }

    #[test]
    fn serde_round_trip() {
        let report = ComplianceReport {
            level: ComplianceLevel::Warn,
            findings: vec![
                ComplianceFinding::warn("peak-too-hot", "too hot", Some(-0.5)),
                ComplianceFinding::pass("clean", "ok"),
            ],
            peak_dbfs: -0.5,
            rms_dbfs: -12.0,
            dc_offset: 0.001,
            clip_count: 0,
            nan_count: 0,
            silence_ratio: 0.02,
            duration_seconds: 1.0,
        };
        let json = serde_json::to_string(&report).unwrap();
        // snake_case enums must be on the wire.
        assert!(json.contains("\"level\":\"warn\""));
        let back: ComplianceReport = serde_json::from_str(&json).unwrap();
        assert_eq!(report, back);
    }
}
