//! EQ curve representation

use serde::{Deserialize, Serialize};

/// Single frequency band in EQ curve
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct FrequencyBand {
    /// Center frequency in Hz
    pub freq: f32,

    /// Gain in dB
    pub gain_db: f32,

    /// Q factor (bandwidth)
    pub q: f32,

    /// Confidence in this band (0.0 - 1.0)
    pub confidence: f32,
}

impl FrequencyBand {
    /// Create new frequency band
    pub fn new(freq: f32, gain_db: f32, q: f32) -> Self {
        Self {
            freq,
            gain_db,
            q,
            confidence: 1.0,
        }
    }

    /// Create band with confidence
    pub fn with_confidence(freq: f32, gain_db: f32, q: f32, confidence: f32) -> Self {
        Self {
            freq,
            gain_db,
            q,
            confidence,
        }
    }

    /// Get bandwidth in octaves
    pub fn bandwidth_octaves(&self) -> f32 {
        if self.q > 0.0 {
            1.0 / self.q
        } else {
            f32::INFINITY
        }
    }

    /// Get lower frequency bound (-3dB point)
    pub fn lower_freq(&self) -> f32 {
        self.freq / 2.0f32.powf(0.5 / self.q.max(0.1))
    }

    /// Get upper frequency bound (-3dB point)
    pub fn upper_freq(&self) -> f32 {
        self.freq * 2.0f32.powf(0.5 / self.q.max(0.1))
    }
}

/// Complete EQ curve for matching
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqCurve {
    /// Frequency bands
    pub bands: Vec<FrequencyBand>,

    /// Sample rate this curve was computed for
    pub sample_rate: u32,

    /// Overall gain adjustment (dB)
    pub global_gain_db: f32,

    /// Match quality score
    pub quality: f32,
}

impl EqCurve {
    /// Create empty EQ curve
    pub fn new(sample_rate: u32) -> Self {
        Self {
            bands: Vec::new(),
            sample_rate,
            global_gain_db: 0.0,
            quality: 0.0,
        }
    }

    /// Create flat EQ curve with given number of bands
    pub fn flat(num_bands: usize, min_freq: f32, max_freq: f32, sample_rate: u32) -> Self {
        let log_min = min_freq.ln();
        let log_max = max_freq.ln();

        let bands: Vec<FrequencyBand> = (0..num_bands)
            .map(|i| {
                let t = i as f32 / (num_bands - 1).max(1) as f32;
                let freq = (log_min + t * (log_max - log_min)).exp();
                FrequencyBand::new(freq, 0.0, 1.0)
            })
            .collect();

        Self {
            bands,
            sample_rate,
            global_gain_db: 0.0,
            quality: 1.0,
        }
    }

    /// Get gain at specific frequency (interpolated)
    pub fn gain_at(&self, freq: f32) -> f32 {
        if self.bands.is_empty() {
            return self.global_gain_db;
        }

        // Find surrounding bands
        let mut lower_idx = 0;
        let mut upper_idx = self.bands.len() - 1;

        for (i, band) in self.bands.iter().enumerate() {
            if band.freq <= freq {
                lower_idx = i;
            }
            if band.freq >= freq && i < upper_idx {
                upper_idx = i;
                break;
            }
        }

        if lower_idx == upper_idx {
            return self.bands[lower_idx].gain_db + self.global_gain_db;
        }

        // Log-linear interpolation
        let lower = &self.bands[lower_idx];
        let upper = &self.bands[upper_idx];

        let log_freq = freq.ln();
        let log_lower = lower.freq.ln();
        let log_upper = upper.freq.ln();

        let t = (log_freq - log_lower) / (log_upper - log_lower);
        let gain = lower.gain_db + t * (upper.gain_db - lower.gain_db);

        gain + self.global_gain_db
    }

    /// Get maximum gain in curve
    pub fn max_gain_db(&self) -> f32 {
        self.bands
            .iter()
            .map(|b| b.gain_db)
            .fold(f32::NEG_INFINITY, f32::max)
            + self.global_gain_db
    }

    /// Get minimum gain in curve
    pub fn min_gain_db(&self) -> f32 {
        self.bands
            .iter()
            .map(|b| b.gain_db)
            .fold(f32::INFINITY, f32::min)
            + self.global_gain_db
    }

    /// Get total gain range
    pub fn gain_range_db(&self) -> f32 {
        self.max_gain_db() - self.min_gain_db()
    }

    /// Apply intensity scaling (0.0 = flat, 1.0 = full)
    pub fn scale(&mut self, intensity: f32) {
        let intensity = intensity.clamp(0.0, 1.0);

        for band in &mut self.bands {
            band.gain_db *= intensity;
        }
        self.global_gain_db *= intensity;
    }

    /// Smooth the curve (moving average)
    pub fn smooth(&mut self, window_size: usize) {
        if window_size < 2 || self.bands.len() < window_size {
            return;
        }

        let half_window = window_size / 2;
        let gains: Vec<f32> = self.bands.iter().map(|b| b.gain_db).collect();

        for (i, band) in self.bands.iter_mut().enumerate() {
            let start = i.saturating_sub(half_window);
            let end = (i + half_window + 1).min(gains.len());

            let sum: f32 = gains[start..end].iter().sum();
            band.gain_db = sum / (end - start) as f32;
        }
    }

    /// Limit maximum gain
    pub fn limit_gain(&mut self, max_db: f32) {
        for band in &mut self.bands {
            band.gain_db = band.gain_db.clamp(-max_db, max_db);
        }
        self.global_gain_db = self.global_gain_db.clamp(-max_db, max_db);
    }

    /// Export to frequency/gain pairs for visualization
    pub fn to_points(&self) -> Vec<(f32, f32)> {
        self.bands
            .iter()
            .map(|b| (b.freq, b.gain_db + self.global_gain_db))
            .collect()
    }

    /// Create high-resolution frequency response
    pub fn to_frequency_response(
        &self,
        num_points: usize,
        min_freq: f32,
        max_freq: f32,
    ) -> Vec<(f32, f32)> {
        let log_min = min_freq.ln();
        let log_max = max_freq.ln();

        (0..num_points)
            .map(|i| {
                let t = i as f32 / (num_points - 1).max(1) as f32;
                let freq = (log_min + t * (log_max - log_min)).exp();
                (freq, self.gain_at(freq))
            })
            .collect()
    }
}

impl Default for EqCurve {
    fn default() -> Self {
        Self::new(44100)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_flat_curve() {
        let curve = EqCurve::flat(10, 20.0, 20000.0, 44100);
        assert_eq!(curve.bands.len(), 10);

        // All gains should be 0
        for band in &curve.bands {
            assert!((band.gain_db - 0.0).abs() < 0.001);
        }
    }

    #[test]
    fn test_gain_interpolation() {
        let mut curve = EqCurve::new(44100);
        curve.bands.push(FrequencyBand::new(100.0, 0.0, 1.0));
        curve.bands.push(FrequencyBand::new(1000.0, 10.0, 1.0));
        curve.bands.push(FrequencyBand::new(10000.0, 0.0, 1.0));

        // Check interpolation at midpoint
        let gain_at_316 = curve.gain_at(316.0); // geometric mean of 100 and 1000
        assert!(gain_at_316 > 0.0 && gain_at_316 < 10.0);
    }

    #[test]
    fn test_scale() {
        let mut curve = EqCurve::new(44100);
        curve.bands.push(FrequencyBand::new(1000.0, 10.0, 1.0));

        curve.scale(0.5);
        assert!((curve.bands[0].gain_db - 5.0).abs() < 0.001);

        curve.scale(0.0);
        assert!((curve.bands[0].gain_db - 0.0).abs() < 0.001);
    }
}
