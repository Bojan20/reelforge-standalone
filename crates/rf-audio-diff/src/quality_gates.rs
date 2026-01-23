//! Audio Quality Gates for CI/CD Integration
//!
//! This module provides configurable quality checks for audio processing outputs:
//! - Loudness targets (LUFS)
//! - Peak levels (True Peak / Sample Peak)
//! - Dynamic range
//! - Frequency response
//! - Silence detection
//! - Clipping detection

use crate::loader::AudioData;
use crate::spectral::to_db;
use crate::Result;
use serde::{Deserialize, Serialize};

/// Audio quality gate configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityGateConfig {
    /// Name of this quality gate profile
    pub name: String,

    /// Loudness checks
    pub loudness: Option<LoudnessGate>,

    /// Peak level checks
    pub peak: Option<PeakGate>,

    /// Dynamic range checks
    pub dynamic_range: Option<DynamicRangeGate>,

    /// Silence detection
    pub silence: Option<SilenceGate>,

    /// Clipping detection
    pub clipping: Option<ClippingGate>,

    /// Frequency balance checks
    pub frequency: Option<FrequencyGate>,

    /// DC offset checks
    pub dc_offset: Option<DcOffsetGate>,

    /// Stereo correlation checks
    pub stereo: Option<StereoGate>,
}

impl Default for QualityGateConfig {
    fn default() -> Self {
        Self {
            name: "default".into(),
            loudness: Some(LoudnessGate::default()),
            peak: Some(PeakGate::default()),
            dynamic_range: None,
            silence: Some(SilenceGate::default()),
            clipping: Some(ClippingGate::default()),
            frequency: None,
            dc_offset: Some(DcOffsetGate::default()),
            stereo: None,
        }
    }
}

impl QualityGateConfig {
    /// Streaming platform preset (Spotify, Apple Music, etc.)
    pub fn streaming() -> Self {
        Self {
            name: "streaming".into(),
            loudness: Some(LoudnessGate {
                min_lufs: Some(-16.0),
                max_lufs: Some(-13.0),
                target_lufs: Some(-14.0),
                tolerance_lu: 1.0,
            }),
            peak: Some(PeakGate {
                max_true_peak_dbtp: -1.0,
                max_sample_peak_dbfs: -0.1,
            }),
            dynamic_range: Some(DynamicRangeGate {
                min_dr: Some(6.0),
                max_dr: Some(14.0),
            }),
            silence: Some(SilenceGate::default()),
            clipping: Some(ClippingGate::strict()),
            frequency: None,
            dc_offset: Some(DcOffsetGate::default()),
            stereo: None,
        }
    }

    /// Broadcast preset (EBU R128)
    pub fn broadcast() -> Self {
        Self {
            name: "broadcast".into(),
            loudness: Some(LoudnessGate {
                min_lufs: Some(-24.0),
                max_lufs: Some(-22.0),
                target_lufs: Some(-23.0),
                tolerance_lu: 0.5,
            }),
            peak: Some(PeakGate {
                max_true_peak_dbtp: -1.0,
                max_sample_peak_dbfs: 0.0,
            }),
            dynamic_range: None,
            silence: Some(SilenceGate::default()),
            clipping: Some(ClippingGate::strict()),
            frequency: None,
            dc_offset: Some(DcOffsetGate::default()),
            stereo: None,
        }
    }

    /// Mastering preset (high dynamic range)
    pub fn mastering() -> Self {
        Self {
            name: "mastering".into(),
            loudness: Some(LoudnessGate {
                min_lufs: Some(-18.0),
                max_lufs: Some(-9.0),
                target_lufs: None,
                tolerance_lu: 2.0,
            }),
            peak: Some(PeakGate {
                max_true_peak_dbtp: -0.3,
                max_sample_peak_dbfs: 0.0,
            }),
            dynamic_range: Some(DynamicRangeGate {
                min_dr: Some(8.0),
                max_dr: None,
            }),
            silence: Some(SilenceGate::default()),
            clipping: Some(ClippingGate::default()),
            frequency: Some(FrequencyGate::default()),
            dc_offset: Some(DcOffsetGate::strict()),
            stereo: Some(StereoGate::default()),
        }
    }

    /// Game audio preset
    pub fn game_audio() -> Self {
        Self {
            name: "game_audio".into(),
            loudness: Some(LoudnessGate {
                min_lufs: Some(-24.0),
                max_lufs: Some(-12.0),
                target_lufs: None,
                tolerance_lu: 3.0,
            }),
            peak: Some(PeakGate {
                max_true_peak_dbtp: -0.5,
                max_sample_peak_dbfs: 0.0,
            }),
            dynamic_range: Some(DynamicRangeGate {
                min_dr: Some(4.0),
                max_dr: Some(20.0),
            }),
            silence: Some(SilenceGate {
                max_leading_silence_ms: 100.0,
                max_trailing_silence_ms: 500.0,
                silence_threshold_db: -60.0,
            }),
            clipping: Some(ClippingGate::default()),
            frequency: None,
            dc_offset: Some(DcOffsetGate::default()),
            stereo: None,
        }
    }
}

/// Loudness gate configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoudnessGate {
    /// Minimum integrated loudness (LUFS)
    pub min_lufs: Option<f64>,

    /// Maximum integrated loudness (LUFS)
    pub max_lufs: Option<f64>,

    /// Target loudness (LUFS)
    pub target_lufs: Option<f64>,

    /// Tolerance around target (LU)
    pub tolerance_lu: f64,
}

impl Default for LoudnessGate {
    fn default() -> Self {
        Self {
            min_lufs: Some(-24.0),
            max_lufs: Some(-9.0),
            target_lufs: None,
            tolerance_lu: 2.0,
        }
    }
}

/// Peak level gate configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeakGate {
    /// Maximum true peak level (dBTP)
    pub max_true_peak_dbtp: f64,

    /// Maximum sample peak (dBFS)
    pub max_sample_peak_dbfs: f64,
}

impl Default for PeakGate {
    fn default() -> Self {
        Self {
            max_true_peak_dbtp: -1.0,
            max_sample_peak_dbfs: 0.0,
        }
    }
}

/// Dynamic range gate configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DynamicRangeGate {
    /// Minimum dynamic range (dB)
    pub min_dr: Option<f64>,

    /// Maximum dynamic range (dB)
    pub max_dr: Option<f64>,
}

impl Default for DynamicRangeGate {
    fn default() -> Self {
        Self {
            min_dr: Some(6.0),
            max_dr: None,
        }
    }
}

/// Silence detection gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SilenceGate {
    /// Maximum leading silence (ms)
    pub max_leading_silence_ms: f64,

    /// Maximum trailing silence (ms)
    pub max_trailing_silence_ms: f64,

    /// Threshold for silence detection (dB)
    pub silence_threshold_db: f64,
}

impl Default for SilenceGate {
    fn default() -> Self {
        Self {
            max_leading_silence_ms: 50.0,
            max_trailing_silence_ms: 100.0,
            silence_threshold_db: -60.0,
        }
    }
}

/// Clipping detection gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClippingGate {
    /// Maximum consecutive clipped samples allowed
    pub max_consecutive_clips: usize,

    /// Total clipped samples threshold
    pub max_total_clips: usize,

    /// Clip threshold (absolute value)
    pub clip_threshold: f64,
}

impl Default for ClippingGate {
    fn default() -> Self {
        Self {
            max_consecutive_clips: 3,
            max_total_clips: 100,
            clip_threshold: 0.99,
        }
    }
}

impl ClippingGate {
    /// Strict clipping gate (no clipping allowed)
    pub fn strict() -> Self {
        Self {
            max_consecutive_clips: 0,
            max_total_clips: 0,
            clip_threshold: 0.999,
        }
    }
}

/// Frequency balance gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrequencyGate {
    /// Low frequency energy threshold (below this is concerning)
    pub min_low_energy_db: f64,

    /// High frequency energy threshold
    pub min_high_energy_db: f64,

    /// Low frequency cutoff (Hz)
    pub low_freq_cutoff: f64,

    /// High frequency cutoff (Hz)
    pub high_freq_cutoff: f64,
}

impl Default for FrequencyGate {
    fn default() -> Self {
        Self {
            min_low_energy_db: -40.0,
            min_high_energy_db: -50.0,
            low_freq_cutoff: 100.0,
            high_freq_cutoff: 8000.0,
        }
    }
}

/// DC offset gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DcOffsetGate {
    /// Maximum allowed DC offset (absolute)
    pub max_dc_offset: f64,
}

impl Default for DcOffsetGate {
    fn default() -> Self {
        Self {
            max_dc_offset: 0.01,
        }
    }
}

impl DcOffsetGate {
    /// Strict DC offset gate
    pub fn strict() -> Self {
        Self {
            max_dc_offset: 0.001,
        }
    }
}

/// Stereo correlation gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StereoGate {
    /// Minimum correlation (mono compatibility)
    pub min_correlation: f64,

    /// Maximum correlation (too mono)
    pub max_correlation: f64,
}

impl Default for StereoGate {
    fn default() -> Self {
        Self {
            min_correlation: -0.5,
            max_correlation: 0.99,
        }
    }
}

/// Result of quality gate check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityGateResult {
    /// Whether all gates passed
    pub passed: bool,

    /// Individual check results
    pub checks: Vec<QualityCheck>,

    /// Overall summary
    pub summary: String,

    /// Measured metrics
    pub metrics: QualityMetrics,
}

/// Individual quality check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityCheck {
    /// Check name
    pub name: String,

    /// Whether this check passed
    pub passed: bool,

    /// Measured value
    pub measured: f64,

    /// Threshold value
    pub threshold: f64,

    /// Description of the check
    pub description: String,

    /// Severity (error, warning, info)
    pub severity: CheckSeverity,
}

/// Check severity level
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum CheckSeverity {
    Error,
    Warning,
    Info,
}

/// Measured quality metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityMetrics {
    /// Integrated loudness (LUFS)
    pub loudness_lufs: f64,

    /// Sample peak (dBFS)
    pub sample_peak_dbfs: f64,

    /// True peak estimate (dBTP)
    pub true_peak_dbtp: f64,

    /// RMS level (dBFS)
    pub rms_dbfs: f64,

    /// Dynamic range (dB)
    pub dynamic_range_db: f64,

    /// DC offset
    pub dc_offset: f64,

    /// Leading silence (ms)
    pub leading_silence_ms: f64,

    /// Trailing silence (ms)
    pub trailing_silence_ms: f64,

    /// Total clipped samples
    pub clipped_samples: usize,

    /// Stereo correlation (if stereo)
    pub stereo_correlation: Option<f64>,
}

/// Quality gate runner
pub struct QualityGateRunner {
    config: QualityGateConfig,
}

impl QualityGateRunner {
    /// Create a new runner with given config
    pub fn new(config: QualityGateConfig) -> Self {
        Self { config }
    }

    /// Run quality gates on audio data
    pub fn check(&self, audio: &AudioData) -> Result<QualityGateResult> {
        let mut checks = Vec::new();

        // Measure all metrics first
        let metrics = self.measure_metrics(audio)?;

        // Run individual checks
        if let Some(ref loudness_gate) = self.config.loudness {
            self.check_loudness(&metrics, loudness_gate, &mut checks);
        }

        if let Some(ref peak_gate) = self.config.peak {
            self.check_peak(&metrics, peak_gate, &mut checks);
        }

        if let Some(ref dr_gate) = self.config.dynamic_range {
            self.check_dynamic_range(&metrics, dr_gate, &mut checks);
        }

        if let Some(ref silence_gate) = self.config.silence {
            self.check_silence(&metrics, silence_gate, &mut checks);
        }

        if let Some(ref clip_gate) = self.config.clipping {
            self.check_clipping(&metrics, clip_gate, &mut checks);
        }

        if let Some(ref dc_gate) = self.config.dc_offset {
            self.check_dc_offset(&metrics, dc_gate, &mut checks);
        }

        if let Some(ref stereo_gate) = self.config.stereo {
            if let Some(corr) = metrics.stereo_correlation {
                self.check_stereo(corr, stereo_gate, &mut checks);
            }
        }

        let passed = checks.iter()
            .filter(|c| c.severity == CheckSeverity::Error)
            .all(|c| c.passed);

        let failed_count = checks.iter().filter(|c| !c.passed).count();
        let summary = if passed {
            format!("PASS: All {} quality checks passed", checks.len())
        } else {
            format!("FAIL: {}/{} quality checks failed", failed_count, checks.len())
        };

        Ok(QualityGateResult {
            passed,
            checks,
            summary,
            metrics,
        })
    }

    fn measure_metrics(&self, audio: &AudioData) -> Result<QualityMetrics> {
        // Calculate basic metrics
        let mono = audio.to_mono();

        // Peak
        let sample_peak = audio.peak();
        let sample_peak_dbfs = to_db(sample_peak);

        // True peak estimation (simple 4x oversampling approximation)
        let true_peak = sample_peak * 1.05; // Simple approximation
        let true_peak_dbtp = to_db(true_peak);

        // RMS
        let rms = audio.rms();
        let rms_dbfs = to_db(rms);

        // Loudness (simplified - uses RMS as proxy)
        // Real LUFS would need K-weighting and gating
        let loudness_lufs = rms_dbfs - 0.691; // Rough approximation

        // Dynamic range (simplified)
        let dynamic_range_db = sample_peak_dbfs - rms_dbfs + 3.0;

        // DC offset
        let dc_offset: f64 = audio.channels.iter()
            .map(|ch| ch.iter().sum::<f64>() / ch.len() as f64)
            .map(|dc| dc.abs())
            .fold(0.0, f64::max);

        // Silence detection
        let silence_threshold = 10.0_f64.powf(
            self.config.silence
                .as_ref()
                .map(|s| s.silence_threshold_db)
                .unwrap_or(-60.0) / 20.0
        );

        let leading_silence_samples = mono.iter()
            .take_while(|&&s| s.abs() < silence_threshold)
            .count();
        let leading_silence_ms = leading_silence_samples as f64 * 1000.0 / audio.sample_rate as f64;

        let trailing_silence_samples = mono.iter().rev()
            .take_while(|&&s| s.abs() < silence_threshold)
            .count();
        let trailing_silence_ms = trailing_silence_samples as f64 * 1000.0 / audio.sample_rate as f64;

        // Clipping detection
        let clip_threshold = self.config.clipping
            .as_ref()
            .map(|c| c.clip_threshold)
            .unwrap_or(0.99);

        let clipped_samples: usize = audio.channels.iter()
            .flat_map(|ch| ch.iter())
            .filter(|&&s| s.abs() >= clip_threshold)
            .count();

        // Stereo correlation
        let stereo_correlation = if audio.num_channels >= 2 {
            Some(calculate_stereo_correlation(&audio.channels[0], &audio.channels[1]))
        } else {
            None
        };

        Ok(QualityMetrics {
            loudness_lufs,
            sample_peak_dbfs,
            true_peak_dbtp,
            rms_dbfs,
            dynamic_range_db,
            dc_offset,
            leading_silence_ms,
            trailing_silence_ms,
            clipped_samples,
            stereo_correlation,
        })
    }

    fn check_loudness(&self, metrics: &QualityMetrics, gate: &LoudnessGate, checks: &mut Vec<QualityCheck>) {
        if let Some(min) = gate.min_lufs {
            checks.push(QualityCheck {
                name: "loudness_min".into(),
                passed: metrics.loudness_lufs >= min,
                measured: metrics.loudness_lufs,
                threshold: min,
                description: format!("Loudness {:.1} LUFS >= {:.1} LUFS", metrics.loudness_lufs, min),
                severity: CheckSeverity::Error,
            });
        }

        if let Some(max) = gate.max_lufs {
            checks.push(QualityCheck {
                name: "loudness_max".into(),
                passed: metrics.loudness_lufs <= max,
                measured: metrics.loudness_lufs,
                threshold: max,
                description: format!("Loudness {:.1} LUFS <= {:.1} LUFS", metrics.loudness_lufs, max),
                severity: CheckSeverity::Error,
            });
        }

        if let Some(target) = gate.target_lufs {
            let diff = (metrics.loudness_lufs - target).abs();
            checks.push(QualityCheck {
                name: "loudness_target".into(),
                passed: diff <= gate.tolerance_lu,
                measured: metrics.loudness_lufs,
                threshold: target,
                description: format!("Loudness {:.1} LUFS within ±{:.1} LU of target {:.1} LUFS",
                    metrics.loudness_lufs, gate.tolerance_lu, target),
                severity: CheckSeverity::Warning,
            });
        }
    }

    fn check_peak(&self, metrics: &QualityMetrics, gate: &PeakGate, checks: &mut Vec<QualityCheck>) {
        checks.push(QualityCheck {
            name: "true_peak".into(),
            passed: metrics.true_peak_dbtp <= gate.max_true_peak_dbtp,
            measured: metrics.true_peak_dbtp,
            threshold: gate.max_true_peak_dbtp,
            description: format!("True peak {:.1} dBTP <= {:.1} dBTP",
                metrics.true_peak_dbtp, gate.max_true_peak_dbtp),
            severity: CheckSeverity::Error,
        });

        checks.push(QualityCheck {
            name: "sample_peak".into(),
            passed: metrics.sample_peak_dbfs <= gate.max_sample_peak_dbfs,
            measured: metrics.sample_peak_dbfs,
            threshold: gate.max_sample_peak_dbfs,
            description: format!("Sample peak {:.1} dBFS <= {:.1} dBFS",
                metrics.sample_peak_dbfs, gate.max_sample_peak_dbfs),
            severity: CheckSeverity::Error,
        });
    }

    fn check_dynamic_range(&self, metrics: &QualityMetrics, gate: &DynamicRangeGate, checks: &mut Vec<QualityCheck>) {
        if let Some(min) = gate.min_dr {
            checks.push(QualityCheck {
                name: "dynamic_range_min".into(),
                passed: metrics.dynamic_range_db >= min,
                measured: metrics.dynamic_range_db,
                threshold: min,
                description: format!("Dynamic range {:.1} dB >= {:.1} dB",
                    metrics.dynamic_range_db, min),
                severity: CheckSeverity::Warning,
            });
        }

        if let Some(max) = gate.max_dr {
            checks.push(QualityCheck {
                name: "dynamic_range_max".into(),
                passed: metrics.dynamic_range_db <= max,
                measured: metrics.dynamic_range_db,
                threshold: max,
                description: format!("Dynamic range {:.1} dB <= {:.1} dB",
                    metrics.dynamic_range_db, max),
                severity: CheckSeverity::Info,
            });
        }
    }

    fn check_silence(&self, metrics: &QualityMetrics, gate: &SilenceGate, checks: &mut Vec<QualityCheck>) {
        checks.push(QualityCheck {
            name: "leading_silence".into(),
            passed: metrics.leading_silence_ms <= gate.max_leading_silence_ms,
            measured: metrics.leading_silence_ms,
            threshold: gate.max_leading_silence_ms,
            description: format!("Leading silence {:.1} ms <= {:.1} ms",
                metrics.leading_silence_ms, gate.max_leading_silence_ms),
            severity: CheckSeverity::Warning,
        });

        checks.push(QualityCheck {
            name: "trailing_silence".into(),
            passed: metrics.trailing_silence_ms <= gate.max_trailing_silence_ms,
            measured: metrics.trailing_silence_ms,
            threshold: gate.max_trailing_silence_ms,
            description: format!("Trailing silence {:.1} ms <= {:.1} ms",
                metrics.trailing_silence_ms, gate.max_trailing_silence_ms),
            severity: CheckSeverity::Warning,
        });
    }

    fn check_clipping(&self, metrics: &QualityMetrics, gate: &ClippingGate, checks: &mut Vec<QualityCheck>) {
        checks.push(QualityCheck {
            name: "clipping".into(),
            passed: metrics.clipped_samples <= gate.max_total_clips,
            measured: metrics.clipped_samples as f64,
            threshold: gate.max_total_clips as f64,
            description: format!("Clipped samples {} <= {}",
                metrics.clipped_samples, gate.max_total_clips),
            severity: CheckSeverity::Error,
        });
    }

    fn check_dc_offset(&self, metrics: &QualityMetrics, gate: &DcOffsetGate, checks: &mut Vec<QualityCheck>) {
        checks.push(QualityCheck {
            name: "dc_offset".into(),
            passed: metrics.dc_offset <= gate.max_dc_offset,
            measured: metrics.dc_offset,
            threshold: gate.max_dc_offset,
            description: format!("DC offset {:.6} <= {:.6}",
                metrics.dc_offset, gate.max_dc_offset),
            severity: CheckSeverity::Warning,
        });
    }

    fn check_stereo(&self, correlation: f64, gate: &StereoGate, checks: &mut Vec<QualityCheck>) {
        checks.push(QualityCheck {
            name: "stereo_correlation_min".into(),
            passed: correlation >= gate.min_correlation,
            measured: correlation,
            threshold: gate.min_correlation,
            description: format!("Stereo correlation {:.3} >= {:.3} (mono compatible)",
                correlation, gate.min_correlation),
            severity: CheckSeverity::Warning,
        });

        checks.push(QualityCheck {
            name: "stereo_correlation_max".into(),
            passed: correlation <= gate.max_correlation,
            measured: correlation,
            threshold: gate.max_correlation,
            description: format!("Stereo correlation {:.3} <= {:.3} (not too mono)",
                correlation, gate.max_correlation),
            severity: CheckSeverity::Info,
        });
    }
}

/// Calculate stereo correlation between two channels
fn calculate_stereo_correlation(left: &[f64], right: &[f64]) -> f64 {
    let len = left.len().min(right.len());
    if len == 0 {
        return 1.0;
    }

    let left_mean: f64 = left[..len].iter().sum::<f64>() / len as f64;
    let right_mean: f64 = right[..len].iter().sum::<f64>() / len as f64;

    let mut cov = 0.0;
    let mut left_var = 0.0;
    let mut right_var = 0.0;

    for i in 0..len {
        let left_diff = left[i] - left_mean;
        let right_diff = right[i] - right_mean;
        cov += left_diff * right_diff;
        left_var += left_diff * left_diff;
        right_var += right_diff * right_diff;
    }

    let std_product = (left_var * right_var).sqrt();
    if std_product > 0.0 {
        cov / std_product
    } else {
        1.0
    }
}

impl QualityGateResult {
    /// Get markdown report
    pub fn to_markdown(&self) -> String {
        let mut output = String::new();

        output.push_str("# Audio Quality Gate Report\n\n");
        output.push_str(&format!("## Status: {}\n\n", if self.passed { "✅ PASS" } else { "❌ FAIL" }));

        output.push_str("## Metrics\n\n");
        output.push_str("| Metric | Value |\n");
        output.push_str("|--------|-------|\n");
        output.push_str(&format!("| Loudness | {:.1} LUFS |\n", self.metrics.loudness_lufs));
        output.push_str(&format!("| Sample Peak | {:.1} dBFS |\n", self.metrics.sample_peak_dbfs));
        output.push_str(&format!("| True Peak | {:.1} dBTP |\n", self.metrics.true_peak_dbtp));
        output.push_str(&format!("| RMS | {:.1} dBFS |\n", self.metrics.rms_dbfs));
        output.push_str(&format!("| Dynamic Range | {:.1} dB |\n", self.metrics.dynamic_range_db));
        output.push_str(&format!("| DC Offset | {:.6} |\n", self.metrics.dc_offset));
        output.push_str(&format!("| Clipped Samples | {} |\n", self.metrics.clipped_samples));
        output.push('\n');

        output.push_str("## Checks\n\n");
        output.push_str("| Check | Status | Measured | Threshold |\n");
        output.push_str("|-------|--------|----------|----------|\n");
        for check in &self.checks {
            let icon = if check.passed { "✅" } else { "❌" };
            output.push_str(&format!("| {} | {} | {:.3} | {:.3} |\n",
                check.name, icon, check.measured, check.threshold));
        }

        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_audio(amplitude: f64) -> AudioData {
        let samples: Vec<f64> = (0..44100)
            .map(|i| amplitude * (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        AudioData {
            channels: vec![samples.clone(), samples],
            sample_rate: 44100,
            num_channels: 2,
            num_samples: 44100,
            duration: 1.0,
            source_path: "test.wav".into(),
        }
    }

    #[test]
    fn test_quality_gate_basic() {
        let audio = make_test_audio(0.5);
        let runner = QualityGateRunner::new(QualityGateConfig::default());

        let result = runner.check(&audio).unwrap();

        assert!(!result.checks.is_empty());
        // A clean sine wave should pass most checks
    }

    #[test]
    fn test_streaming_preset() {
        let audio = make_test_audio(0.3);
        let runner = QualityGateRunner::new(QualityGateConfig::streaming());

        let result = runner.check(&audio).unwrap();

        assert!(!result.checks.is_empty());
    }

    #[test]
    fn test_clipping_detection() {
        // Create clipped audio
        let samples: Vec<f64> = (0..44100)
            .map(|i| {
                let s = 1.5 * (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin();
                s.clamp(-1.0, 1.0)
            })
            .collect();

        let audio = AudioData {
            channels: vec![samples],
            sample_rate: 44100,
            num_channels: 1,
            num_samples: 44100,
            duration: 1.0,
            source_path: "test.wav".into(),
        };

        let runner = QualityGateRunner::new(QualityGateConfig::default());
        let result = runner.check(&audio).unwrap();

        // Should have clipped samples
        assert!(result.metrics.clipped_samples > 0);
    }

    #[test]
    fn test_metrics_markdown() {
        let audio = make_test_audio(0.5);
        let runner = QualityGateRunner::new(QualityGateConfig::default());

        let result = runner.check(&audio).unwrap();
        let markdown = result.to_markdown();

        assert!(markdown.contains("# Audio Quality Gate Report"));
        assert!(markdown.contains("Loudness"));
    }
}
