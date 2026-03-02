use crate::core::config::RtpConfig;
use crate::rtp::models::PacingCurve;

/// Maps RTP percentage to emotional pacing parameters.
pub struct RtpEmotionalMapper;

impl RtpEmotionalMapper {
    /// Compute pacing curve from RTP percentage.
    ///
    /// Higher RTP (98%): Slower build, fewer spikes, lower elasticity.
    /// Lower RTP (88%): Faster build, more frequent spikes, higher elasticity.
    ///
    /// Uses inverse-normalized RTP: intensity = (MAX_RTP - rtp) / (MAX_RTP - MIN_RTP)
    /// So RTP=99 → intensity≈0, RTP=85 → intensity≈1.
    pub fn pacing_curve(rtp: f64, config: &RtpConfig) -> PacingCurve {
        let rtp_clamped = rtp.clamp(crate::MIN_RTP, crate::MAX_RTP);
        let intensity = (crate::MAX_RTP - rtp_clamped) / (crate::MAX_RTP - crate::MIN_RTP);

        PacingCurve {
            build_time_ms: Self::lerp(
                config.build_time_max_ms,
                config.build_time_min_ms,
                intensity,
            ),
            hold_time_ms: config.hold_time_ms * (1.0 - 0.5 * intensity),
            release_time_ms: config.release_time_ms * (1.0 - 0.4 * intensity),
            spike_rate_hz: Self::spike_frequency(rtp, config),
            peak_elasticity: Self::peak_elasticity(rtp, config),
        }
    }

    /// Compute micro-spike frequency from RTP.
    ///
    /// Lower RTP = more frequent micro-spikes (keeps player engaged during
    /// longer dry spells between bigger wins).
    ///
    /// Formula: base_rate × (1 + intensity × spike_rate_scale)
    /// RTP=99 → ~1 Hz (rare spikes)
    /// RTP=85 → ~4 Hz (frequent spikes)
    pub fn spike_frequency(rtp: f64, config: &RtpConfig) -> f64 {
        let rtp_clamped = rtp.clamp(crate::MIN_RTP, crate::MAX_RTP);
        let intensity = (crate::MAX_RTP - rtp_clamped) / (crate::MAX_RTP - crate::MIN_RTP);
        // Quadratic ramp: spikes increase more aggressively at low RTP
        let base_rate = 0.8;
        base_rate + intensity * intensity * config.spike_rate_scale
    }

    /// Compute peak elasticity from RTP.
    ///
    /// Lower RTP = peaks can overshoot more (compensates for lower base intensity
    /// with occasional dramatic spikes).
    ///
    /// RTP=99 → elasticity ≈ 1.0 (no overshoot)
    /// RTP=85 → elasticity ≈ peak_elasticity_max
    pub fn peak_elasticity(rtp: f64, config: &RtpConfig) -> f64 {
        let rtp_clamped = rtp.clamp(crate::MIN_RTP, crate::MAX_RTP);
        let intensity = (crate::MAX_RTP - rtp_clamped) / (crate::MAX_RTP - crate::MIN_RTP);
        // Linear interpolation: 1.0 at high RTP, peak_elasticity_max at low RTP
        1.0 + intensity * (config.peak_elasticity_max - 1.0)
    }

    fn lerp(a: f64, b: f64, t: f64) -> f64 {
        a + t * (b - a)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_config() -> RtpConfig {
        RtpConfig::default()
    }

    #[test]
    fn test_high_rtp_slow_build() {
        let cfg = default_config();
        let pacing = RtpEmotionalMapper::pacing_curve(98.0, &cfg);
        // High RTP → build time close to max
        assert!(
            pacing.build_time_ms > 2000.0,
            "High RTP should have slow build: {}",
            pacing.build_time_ms
        );
    }

    #[test]
    fn test_low_rtp_fast_build() {
        let cfg = default_config();
        let pacing = RtpEmotionalMapper::pacing_curve(88.0, &cfg);
        // Low RTP → build time close to min
        assert!(
            pacing.build_time_ms < 1500.0,
            "Low RTP should have fast build: {}",
            pacing.build_time_ms
        );
    }

    #[test]
    fn test_spike_frequency_increases_with_lower_rtp() {
        let cfg = default_config();
        let high = RtpEmotionalMapper::spike_frequency(98.0, &cfg);
        let low = RtpEmotionalMapper::spike_frequency(88.0, &cfg);
        assert!(
            low > high,
            "Lower RTP should have more spikes: low={low}, high={high}"
        );
    }

    #[test]
    fn test_peak_elasticity_range() {
        let cfg = default_config();
        let at_max = RtpEmotionalMapper::peak_elasticity(99.5, &cfg);
        let at_min = RtpEmotionalMapper::peak_elasticity(85.0, &cfg);
        assert!(
            (at_max - 1.0).abs() < 0.01,
            "At max RTP, elasticity should be ~1.0"
        );
        assert!((at_min - cfg.peak_elasticity_max).abs() < 0.01);
    }

    #[test]
    fn test_clamping() {
        let cfg = default_config();
        // Out-of-range RTP should clamp
        let over = RtpEmotionalMapper::pacing_curve(150.0, &cfg);
        let under = RtpEmotionalMapper::pacing_curve(50.0, &cfg);
        // Both should produce valid results
        assert!(over.build_time_ms > 0.0);
        assert!(under.build_time_ms > 0.0);
    }

    #[test]
    fn test_monotonic_build_time() {
        let cfg = default_config();
        let mut prev = 0.0_f64;
        for rtp_10x in 850..=995 {
            let rtp = rtp_10x as f64 / 10.0;
            let pacing = RtpEmotionalMapper::pacing_curve(rtp, &cfg);
            assert!(
                pacing.build_time_ms >= prev - 0.001,
                "Build time should increase with higher RTP at rtp={rtp}: {} < {}",
                pacing.build_time_ms,
                prev
            );
            prev = pacing.build_time_ms;
        }
    }
}
