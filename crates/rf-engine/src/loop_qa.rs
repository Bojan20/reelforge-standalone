//! Loop QA Harness — Click detector, seam analyzer, drift logger.
//!
//! Used for automated quality assurance of loop seams.
//! All functions are offline-only (not real-time safe).

/// Seam analysis result.
#[derive(Debug, Clone)]
pub struct SeamAnalysis {
    /// Maximum sample-to-sample discontinuity at any wrap point (0.0–1.0)
    pub max_discontinuity: f32,
    /// Maximum RMS level change across wrap in dB
    pub max_delta_db: f32,
    /// Whether the analysis passes quality thresholds
    pub pass: bool,
}

/// Analyzes rendered audio for clicks at loop seams.
pub fn analyze_seam_quality(
    output: &[f32],
    wrap_positions: &[usize],
    window_samples: usize,
) -> SeamAnalysis {
    let mut max_discontinuity: f32 = 0.0;
    let mut max_delta_db: f32 = f32::NEG_INFINITY;

    for &wrap_frame in wrap_positions {
        let idx = wrap_frame * 2; // stereo interleaved
        if idx >= output.len() || idx < 2 {
            continue;
        }

        // Sample-to-sample difference at wrap point
        let delta_l = (output[idx] - output[idx - 2]).abs();
        let delta_r = if idx + 1 < output.len() && idx >= 1 {
            (output[idx + 1] - output[idx - 1]).abs()
        } else {
            0.0
        };
        let delta = delta_l.max(delta_r);
        max_discontinuity = max_discontinuity.max(delta);

        // RMS before and after
        let start_before = idx.saturating_sub(window_samples * 2);
        let end_after = (idx + window_samples * 2).min(output.len());

        let rms_before = rms(&output[start_before..idx]);
        let rms_after = rms(&output[idx..end_after]);

        if rms_before > 0.0 && rms_after > 0.0 {
            let delta_db = 20.0 * (rms_after / rms_before).log10();
            max_delta_db = max_delta_db.max(delta_db.abs());
        }
    }

    if max_delta_db == f32::NEG_INFINITY {
        max_delta_db = 0.0;
    }

    SeamAnalysis {
        max_discontinuity,
        max_delta_db,
        pass: max_discontinuity < 0.01 && max_delta_db < 3.0,
    }
}

/// Compute RMS of a buffer.
fn rms(buf: &[f32]) -> f32 {
    if buf.is_empty() {
        return 0.0;
    }
    let sum_sq: f64 = buf.iter().map(|&s| (s as f64) * (s as f64)).sum();
    (sum_sq / buf.len() as f64).sqrt() as f32
}

/// Drift report for loop timing analysis.
#[derive(Debug, Clone)]
pub struct DriftReport {
    pub max_drift_samples: i64,
    pub mean_drift_samples: f64,
    pub cumulative_drift: i64,
    pub pass: bool,
}

/// Drift logger — records expected vs actual wrap positions.
pub struct DriftLogger {
    pub expected_wraps: Vec<u64>,
    pub actual_wraps: Vec<u64>,
}

impl DriftLogger {
    pub fn new() -> Self {
        Self {
            expected_wraps: Vec::new(),
            actual_wraps: Vec::new(),
        }
    }

    pub fn record(&mut self, expected: u64, actual: u64) {
        self.expected_wraps.push(expected);
        self.actual_wraps.push(actual);
    }

    pub fn report(&self) -> DriftReport {
        let drifts: Vec<i64> = self
            .expected_wraps
            .iter()
            .zip(self.actual_wraps.iter())
            .map(|(e, a)| *a as i64 - *e as i64)
            .collect();

        DriftReport {
            max_drift_samples: drifts.iter().map(|d| d.abs()).max().unwrap_or(0),
            mean_drift_samples: if drifts.is_empty() {
                0.0
            } else {
                drifts.iter().sum::<i64>() as f64 / drifts.len() as f64
            },
            cumulative_drift: drifts.iter().sum::<i64>(),
            pass: drifts.iter().all(|d| d.abs() <= 1),
        }
    }
}

impl Default for DriftLogger {
    fn default() -> Self {
        Self::new()
    }
}
