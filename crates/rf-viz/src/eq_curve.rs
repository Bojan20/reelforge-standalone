//! EQ curve visualization

use rf_dsp::biquad::{BiquadCoeffs, FilterType};
use std::f64::consts::PI;

/// EQ band for visualization
#[derive(Debug, Clone)]
pub struct EqBand {
    pub filter_type: FilterType,
    pub frequency: f64,
    pub gain_db: f64,
    pub q: f64,
    pub enabled: bool,
}

impl Default for EqBand {
    fn default() -> Self {
        Self {
            filter_type: FilterType::Peaking,
            frequency: 1000.0,
            gain_db: 0.0,
            q: 1.0,
            enabled: true,
        }
    }
}

/// EQ curve calculator
pub struct EqCurve {
    bands: Vec<EqBand>,
    sample_rate: f64,
    num_points: usize,
}

impl EqCurve {
    pub fn new(sample_rate: f64, num_points: usize) -> Self {
        Self {
            bands: Vec::new(),
            sample_rate,
            num_points,
        }
    }

    pub fn add_band(&mut self, band: EqBand) {
        self.bands.push(band);
    }

    pub fn set_bands(&mut self, bands: Vec<EqBand>) {
        self.bands = bands;
    }

    pub fn clear(&mut self) {
        self.bands.clear();
    }

    /// Calculate the combined frequency response
    pub fn calculate(&self) -> Vec<(f64, f64)> {
        let mut points = Vec::with_capacity(self.num_points);

        // Log-spaced frequencies from 20Hz to 20kHz
        let log_min = 20.0_f64.ln();
        let log_max = 20000.0_f64.ln();

        for i in 0..self.num_points {
            let t = i as f64 / (self.num_points - 1) as f64;
            let freq = (log_min + t * (log_max - log_min)).exp();

            let mut total_db = 0.0;

            for band in &self.bands {
                if band.enabled {
                    let response = self.band_response(band, freq);
                    total_db += response;
                }
            }

            points.push((freq, total_db));
        }

        points
    }

    /// Calculate single band response at a frequency
    fn band_response(&self, band: &EqBand, freq: f64) -> f64 {
        let coeffs = match band.filter_type {
            FilterType::Lowpass => BiquadCoeffs::lowpass(band.frequency, band.q, self.sample_rate),
            FilterType::Highpass => BiquadCoeffs::highpass(band.frequency, band.q, self.sample_rate),
            FilterType::Bandpass => BiquadCoeffs::bandpass(band.frequency, band.q, self.sample_rate),
            FilterType::Notch => BiquadCoeffs::notch(band.frequency, band.q, self.sample_rate),
            FilterType::Allpass => BiquadCoeffs::allpass(band.frequency, band.q, self.sample_rate),
            FilterType::Peaking => BiquadCoeffs::peaking(band.frequency, band.q, band.gain_db, self.sample_rate),
            FilterType::LowShelf => BiquadCoeffs::low_shelf(band.frequency, band.q, band.gain_db, self.sample_rate),
            FilterType::HighShelf => BiquadCoeffs::high_shelf(band.frequency, band.q, band.gain_db, self.sample_rate),
            FilterType::Tilt => {
                // Tilt is approximated as low shelf + inverted high shelf
                BiquadCoeffs::peaking(band.frequency, band.q, band.gain_db, self.sample_rate)
            }
        };

        // Calculate frequency response magnitude
        let omega = 2.0 * PI * freq / self.sample_rate;
        let cos_omega = omega.cos();
        let sin_omega = omega.sin();

        // H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
        // At z = e^(j*omega): z^-1 = e^(-j*omega) = cos(omega) - j*sin(omega)

        let z1_re = cos_omega;
        let z1_im = -sin_omega;
        let z2_re = cos_omega * cos_omega - sin_omega * sin_omega; // cos(2*omega)
        let z2_im = -2.0 * sin_omega * cos_omega; // -sin(2*omega)

        // Numerator: b0 + b1*z^-1 + b2*z^-2
        let num_re = coeffs.b0 + coeffs.b1 * z1_re + coeffs.b2 * z2_re;
        let num_im = coeffs.b1 * z1_im + coeffs.b2 * z2_im;

        // Denominator: 1 + a1*z^-1 + a2*z^-2
        let den_re = 1.0 + coeffs.a1 * z1_re + coeffs.a2 * z2_re;
        let den_im = coeffs.a1 * z1_im + coeffs.a2 * z2_im;

        // Magnitude of H(z)
        let num_mag = (num_re * num_re + num_im * num_im).sqrt();
        let den_mag = (den_re * den_re + den_im * den_im).sqrt();

        let magnitude = num_mag / den_mag.max(1e-10);

        // Convert to dB
        20.0 * magnitude.max(1e-10).log10()
    }

    /// Get band count
    pub fn band_count(&self) -> usize {
        self.bands.len()
    }

    /// Get bands
    pub fn bands(&self) -> &[EqBand] {
        &self.bands
    }

    /// Get mutable bands
    pub fn bands_mut(&mut self) -> &mut [EqBand] {
        &mut self.bands
    }
}

/// Simple EQ curve renderer (CPU-based)
pub struct EqCurveRenderer {
    width: u32,
    height: u32,
    min_db: f64,
    max_db: f64,
    grid_color: [u8; 4],
    curve_color: [u8; 4],
    background_color: [u8; 4],
}

impl EqCurveRenderer {
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            min_db: -24.0,
            max_db: 24.0,
            grid_color: [40, 40, 50, 255],
            curve_color: [255, 144, 64, 255], // Orange
            background_color: [18, 18, 22, 255],
        }
    }

    pub fn set_range(&mut self, min_db: f64, max_db: f64) {
        self.min_db = min_db;
        self.max_db = max_db;
    }

    /// Render EQ curve to RGBA buffer
    pub fn render(&self, curve: &[(f64, f64)]) -> Vec<u8> {
        let width = self.width as usize;
        let height = self.height as usize;
        let mut buffer = vec![0u8; width * height * 4];

        // Fill background
        for pixel in buffer.chunks_mut(4) {
            pixel.copy_from_slice(&self.background_color);
        }

        // Draw grid lines
        self.draw_grid(&mut buffer, width, height);

        // Draw curve
        if !curve.is_empty() {
            let log_min = 20.0_f64.ln();
            let log_max = 20000.0_f64.ln();
            let db_range = self.max_db - self.min_db;

            let mut prev_x = None;
            let mut prev_y = None;

            for &(freq, db) in curve {
                // Map frequency to x
                let t = (freq.ln() - log_min) / (log_max - log_min);
                let x = (t * (width - 1) as f64) as i32;

                // Map dB to y
                let db_normalized = (db - self.min_db) / db_range;
                let y = ((1.0 - db_normalized) * (height - 1) as f64) as i32;

                // Draw line from previous point
                if let (Some(px), Some(py)) = (prev_x, prev_y) {
                    self.draw_line(&mut buffer, width, height, px, py, x, y);
                }

                prev_x = Some(x);
                prev_y = Some(y);
            }
        }

        buffer
    }

    fn draw_grid(&self, buffer: &mut [u8], width: usize, height: usize) {
        // Horizontal lines at common dB values
        let db_lines = [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0];
        let db_range = self.max_db - self.min_db;

        for &db in &db_lines {
            if db >= self.min_db && db <= self.max_db {
                let y = ((1.0 - (db - self.min_db) / db_range) * (height - 1) as f64) as usize;
                for x in 0..width {
                    let idx = (y * width + x) * 4;
                    if idx + 3 < buffer.len() {
                        buffer[idx..idx + 4].copy_from_slice(&self.grid_color);
                    }
                }
            }
        }

        // Vertical lines at common frequencies
        let freq_lines: [f64; 8] = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
        let log_min = 20.0_f64.ln();
        let log_max = 20000.0_f64.ln();

        for &freq in &freq_lines {
            let t = (freq.ln() - log_min) / (log_max - log_min);
            let x = (t * (width - 1) as f64) as usize;
            for y in 0..height {
                let idx = (y * width + x) * 4;
                if idx + 3 < buffer.len() {
                    buffer[idx..idx + 4].copy_from_slice(&self.grid_color);
                }
            }
        }
    }

    fn draw_line(&self, buffer: &mut [u8], width: usize, height: usize, x0: i32, y0: i32, x1: i32, y1: i32) {
        // Bresenham's line algorithm
        let dx = (x1 - x0).abs();
        let dy = -(y1 - y0).abs();
        let sx = if x0 < x1 { 1 } else { -1 };
        let sy = if y0 < y1 { 1 } else { -1 };
        let mut err = dx + dy;

        let mut x = x0;
        let mut y = y0;

        loop {
            if x >= 0 && x < width as i32 && y >= 0 && y < height as i32 {
                let idx = (y as usize * width + x as usize) * 4;
                if idx + 3 < buffer.len() {
                    buffer[idx..idx + 4].copy_from_slice(&self.curve_color);
                }
            }

            if x == x1 && y == y1 {
                break;
            }

            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x += sx;
            }
            if e2 <= dx {
                err += dx;
                y += sy;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_eq_curve() {
        let mut curve = EqCurve::new(48000.0, 100);

        curve.add_band(EqBand {
            filter_type: FilterType::Peaking,
            frequency: 1000.0,
            gain_db: 6.0,
            q: 1.0,
            enabled: true,
        });

        let points = curve.calculate();
        assert_eq!(points.len(), 100);

        // Should have boost around 1kHz
        let peak_idx = points.iter().position(|(f, _)| *f >= 1000.0).unwrap();
        assert!(points[peak_idx].1 > 3.0); // At least 3dB boost near center
    }
}
