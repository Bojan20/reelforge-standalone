use crate::core::config::FatigueConfig;

/// Tracks listener fatigue across a session.
///
/// Monitors 4 metrics:
/// 1. Running RMS average (exponential window)
/// 2. Cumulative HF energy (8kHz+ band)
/// 3. Transient density (events per minute)
/// 4. Stereo width time-on
pub struct SessionFatigueTracker {
    // ═══ RMS TRACKING ═══
    /// Exponentially-weighted RMS average (dB).
    rms_avg_db: f64,
    /// Smoothing coefficient for exponential window.
    rms_alpha: f64,
    /// Whether we've received any RMS data.
    rms_initialized: bool,

    // ═══ HF TRACKING ═══
    /// Cumulative HF energy (dB·s). Only accumulates when above threshold.
    hf_cumulative_db_s: f64,

    // ═══ TRANSIENT TRACKING ═══
    /// Ring buffer of transient timestamps (ms since session start).
    transient_times: Vec<u64>,
    /// Previous RMS level for onset detection.
    prev_rms_db: f64,

    // ═══ STEREO TRACKING ═══
    /// Cumulative time with wide stereo (ms).
    stereo_wide_time_ms: u64,
    /// Whether stereo is currently "wide" (width > 0.7).
    stereo_is_wide: bool,

    // ═══ SESSION ═══
    /// Total elapsed time (ms).
    elapsed_ms: u64,
}

impl SessionFatigueTracker {
    pub fn new(config: &FatigueConfig) -> Self {
        // Compute exponential smoothing alpha from window size.
        // alpha = 1 - exp(-tick_interval / window_size)
        // For 50ms tick, 10s window: alpha ≈ 0.005
        let tick_s = 0.05; // 50ms default tick
        let alpha = 1.0 - (-tick_s / config.rms_window_s).exp();

        Self {
            rms_avg_db: -60.0,
            rms_alpha: alpha,
            rms_initialized: false,
            hf_cumulative_db_s: 0.0,
            transient_times: Vec::with_capacity(256),
            prev_rms_db: -60.0,
            stereo_wide_time_ms: 0,
            stereo_is_wide: false,
            elapsed_ms: 0,
        }
    }

    /// Called every tick (typically 50ms).
    pub fn tick(&mut self, elapsed_ms: u64, config: &FatigueConfig) {
        self.elapsed_ms += elapsed_ms;

        // Clean old transient entries (keep only last 60 seconds)
        let cutoff = self.elapsed_ms.saturating_sub(60_000);
        self.transient_times.retain(|&t| t > cutoff);

        // Track stereo width time
        if self.stereo_is_wide {
            self.stereo_wide_time_ms += elapsed_ms;
        }

        // Recalculate RMS alpha if config changed
        let tick_s = elapsed_ms as f64 / 1000.0;
        self.rms_alpha = 1.0 - (-tick_s / config.rms_window_s).exp();
    }

    /// Update with current RMS level (dB).
    pub fn update_rms(&mut self, rms_db: f64, config: &FatigueConfig) {
        if !self.rms_initialized {
            self.rms_avg_db = rms_db;
            self.rms_initialized = true;
        } else {
            // Exponential moving average
            self.rms_avg_db = self.rms_avg_db * (1.0 - self.rms_alpha) + rms_db * self.rms_alpha;
        }

        // Onset detection: sharp spike = transient
        let delta = rms_db - self.prev_rms_db;
        if delta > config.transient_detect_mult * 3.0 {
            // ~7.5 dB spike qualifies as transient at default mult=2.5
            self.transient_times.push(self.elapsed_ms);
        }
        self.prev_rms_db = rms_db;
    }

    /// Update with current HF band energy (dB).
    pub fn update_hf(&mut self, hf_db: f64) {
        // Accumulate HF energy: integrate dB over time (dB·s).
        // Only accumulate when HF is significant (above -30 dB).
        if hf_db > -30.0 {
            let tick_s = 0.05; // 50ms tick
            // Convert dB to linear power, integrate, convert back
            let power = 10.0_f64.powf(hf_db / 10.0);
            self.hf_cumulative_db_s += power * tick_s;
        }
    }

    /// Update stereo width state.
    pub fn update_stereo_width(&mut self, width: f64) {
        self.stereo_is_wide = width > 0.7;
    }

    /// Get current running RMS average (dB).
    pub fn rms_exposure_avg_db(&self) -> f64 {
        self.rms_avg_db
    }

    /// Get cumulative HF energy (linear power·seconds).
    pub fn hf_exposure_cumulative(&self) -> f64 {
        self.hf_cumulative_db_s
    }

    /// Get transient density (events per minute).
    pub fn transient_density_per_min(&self) -> f64 {
        self.transient_times.len() as f64 // Already filtered to last 60s
    }

    /// Get stereo width time-on (minutes).
    pub fn stereo_time_on_min(&self) -> f64 {
        self.stereo_wide_time_ms as f64 / 60_000.0
    }

    /// Get total session duration (seconds).
    pub fn session_duration_s(&self) -> f64 {
        self.elapsed_ms as f64 / 1000.0
    }

    /// Compute composite fatigue index (0.0 = fresh, 1.0 = fatigued).
    ///
    /// Weighted combination of all 4 metrics normalized against thresholds.
    /// Each metric contributes 0.0-1.0, weights sum to 1.0.
    pub fn fatigue_index(&self, config: &FatigueConfig) -> f64 {
        // Normalize each metric: 0.0 below threshold, 0.0-1.0 approaching, 1.0 at threshold
        let rms_norm = if config.rms_threshold_db >= 0.0 {
            0.0
        } else {
            // RMS is negative dB, threshold is negative. Higher (less negative) = more fatigue.
            let ratio = (self.rms_avg_db - config.rms_threshold_db + 6.0)
                / (-config.rms_threshold_db + 6.0);
            ratio.clamp(0.0, 1.0)
        };

        let hf_norm = (self.hf_cumulative_db_s / config.hf_threshold_db_s).clamp(0.0, 1.0);

        let transient_norm =
            (self.transient_density_per_min() / config.transient_threshold_per_min).clamp(0.0, 1.0);

        let stereo_norm =
            (self.stereo_time_on_min() / config.stereo_time_threshold_min).clamp(0.0, 1.0);

        // Weighted combination: RMS and HF are most impactful
        let fatigue = rms_norm * 0.35 + hf_norm * 0.30 + transient_norm * 0.20 + stereo_norm * 0.15;
        fatigue.clamp(0.0, 1.0)
    }

    /// Reset all tracking state.
    pub fn reset(&mut self) {
        self.rms_avg_db = -60.0;
        self.rms_initialized = false;
        self.hf_cumulative_db_s = 0.0;
        self.transient_times.clear();
        self.prev_rms_db = -60.0;
        self.stereo_wide_time_ms = 0;
        self.stereo_is_wide = false;
        self.elapsed_ms = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> FatigueConfig {
        FatigueConfig::default()
    }

    #[test]
    fn test_fresh_session() {
        let cfg = default_config();
        let tracker = SessionFatigueTracker::new(&cfg);
        assert!(tracker.fatigue_index(&cfg) < 0.01, "Fresh session should have near-zero fatigue");
    }

    #[test]
    fn test_rms_averaging() {
        let cfg = default_config();
        let mut tracker = SessionFatigueTracker::new(&cfg);

        // Feed constant -10 dB for many ticks
        for _ in 0..200 {
            tracker.tick(50, &cfg);
            tracker.update_rms(-10.0, &cfg);
        }

        // Should converge near -10 dB
        assert!((tracker.rms_exposure_avg_db() - (-10.0)).abs() < 1.0);
    }

    #[test]
    fn test_hf_accumulation() {
        let cfg = default_config();
        let mut tracker = SessionFatigueTracker::new(&cfg);

        // Feed HF energy for 100 ticks (5 seconds)
        for _ in 0..100 {
            tracker.tick(50, &cfg);
            tracker.update_hf(-6.0); // -6 dB HF energy
        }

        assert!(tracker.hf_exposure_cumulative() > 0.0, "HF energy should accumulate");
    }

    #[test]
    fn test_transient_detection() {
        let cfg = default_config();
        let mut tracker = SessionFatigueTracker::new(&cfg);

        // Simulate a transient: quiet → loud spike
        tracker.tick(50, &cfg);
        tracker.update_rms(-30.0, &cfg);
        tracker.tick(50, &cfg);
        tracker.update_rms(-5.0, &cfg); // +25 dB spike → definite transient

        assert!(tracker.transient_density_per_min() >= 1.0);
    }

    #[test]
    fn test_stereo_fatigue() {
        let cfg = default_config();
        let mut tracker = SessionFatigueTracker::new(&cfg);

        tracker.update_stereo_width(0.9); // wide
        for _ in 0..1200 {
            // 1200 × 50ms = 60 seconds
            tracker.tick(50, &cfg);
        }

        assert!(tracker.stereo_time_on_min() > 0.9, "Should track ~1 minute of stereo");
    }

    #[test]
    fn test_fatigue_increases_over_time() {
        let cfg = default_config();
        let mut tracker = SessionFatigueTracker::new(&cfg);

        let early = tracker.fatigue_index(&cfg);

        // Simulate sustained loud session
        tracker.update_stereo_width(0.9);
        for _ in 0..2000 {
            tracker.tick(50, &cfg);
            tracker.update_rms(-8.0, &cfg);
            tracker.update_hf(-6.0);
        }

        let late = tracker.fatigue_index(&cfg);
        assert!(late > early, "Fatigue should increase: early={early}, late={late}");
    }

    #[test]
    fn test_reset() {
        let cfg = default_config();
        let mut tracker = SessionFatigueTracker::new(&cfg);

        tracker.update_rms(-5.0, &cfg);
        tracker.update_hf(-3.0);
        tracker.tick(50, &cfg);

        tracker.reset();
        assert!(tracker.fatigue_index(&cfg) < 0.01);
        assert_eq!(tracker.session_duration_s(), 0.0);
    }
}
