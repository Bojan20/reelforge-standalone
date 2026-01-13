//! 3D Spectrogram Visualization
//!
//! GPU-accelerated spectrogram with:
//! - Real-time FFT analysis
//! - 3D waterfall display
//! - Multiple color maps (viridis, magma, plasma, turbo)
//! - Configurable frequency/time resolution
//! - Peak hold and smoothing

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════
// COLOR MAPS
// ═══════════════════════════════════════════════════════════════════════════

/// Spectrogram color map
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ColorMap {
    /// Viridis (perceptually uniform, colorblind-friendly)
    #[default]
    Viridis,
    /// Magma (dark to bright yellow)
    Magma,
    /// Plasma (purple to yellow)
    Plasma,
    /// Turbo (rainbow)
    Turbo,
    /// Inferno (dark to bright)
    Inferno,
    /// Grayscale
    Grayscale,
    /// Pro Audio (dark blue to red)
    ProAudio,
}

impl ColorMap {
    /// Sample the color map at position t (0.0-1.0)
    /// Returns (r, g, b, a) in 0.0-1.0 range
    pub fn sample(&self, t: f32) -> [f32; 4] {
        let t = t.clamp(0.0, 1.0);

        match self {
            ColorMap::Viridis => Self::viridis(t),
            ColorMap::Magma => Self::magma(t),
            ColorMap::Plasma => Self::plasma(t),
            ColorMap::Turbo => Self::turbo(t),
            ColorMap::Inferno => Self::inferno(t),
            ColorMap::Grayscale => [t, t, t, 1.0],
            ColorMap::ProAudio => Self::pro_audio(t),
        }
    }

    fn viridis(t: f32) -> [f32; 4] {
        // Simplified viridis approximation
        let r = 0.267 + t * (0.993 - 0.267);
        let g = if t < 0.5 {
            0.004 + t * 2.0 * (0.507 - 0.004)
        } else {
            0.507 + (t - 0.5) * 2.0 * (0.906 - 0.507)
        };
        let b = 0.329 + t * 0.1 * (1.0 - t) * 4.0;
        [r, g, b, 1.0]
    }

    fn magma(t: f32) -> [f32; 4] {
        let r = t * t;
        let g = t * 0.7;
        let b = 0.2 + t * 0.3;
        [r.min(1.0), g.min(1.0), b.min(1.0), 1.0]
    }

    fn plasma(t: f32) -> [f32; 4] {
        let r = 0.05 + t * 0.9;
        let g = t * t * 0.8;
        let b = 0.53 * (1.0 - t) + 0.2;
        [r.min(1.0), g.min(1.0), b.min(1.0), 1.0]
    }

    fn turbo(t: f32) -> [f32; 4] {
        // Rainbow gradient
        let r = (4.0 * t - 1.5).abs().min(1.0);
        let g = (4.0 * t - 0.5).abs().min(1.0);
        let b = (4.0 * t - 2.5).abs().min(1.0);
        [1.0 - r, 1.0 - g, 1.0 - b, 1.0]
    }

    fn inferno(t: f32) -> [f32; 4] {
        let r = t.powf(0.5);
        let g = t * t * 0.8;
        let b = 0.4 * (1.0 - t);
        [r.min(1.0), g.min(1.0), b.min(1.0), 1.0]
    }

    fn pro_audio(t: f32) -> [f32; 4] {
        // Dark blue -> cyan -> green -> yellow -> red
        if t < 0.2 {
            let s = t / 0.2;
            [0.0, 0.0, 0.2 + s * 0.6, 1.0] // Dark to blue
        } else if t < 0.4 {
            let s = (t - 0.2) / 0.2;
            [0.0, s * 0.8, 0.8, 1.0] // Blue to cyan
        } else if t < 0.6 {
            let s = (t - 0.4) / 0.2;
            [0.0, 0.8, 0.8 - s * 0.8, 1.0] // Cyan to green
        } else if t < 0.8 {
            let s = (t - 0.6) / 0.2;
            [s, 0.8, 0.0, 1.0] // Green to yellow
        } else {
            let s = (t - 0.8) / 0.2;
            [1.0, 0.8 - s * 0.8, 0.0, 1.0] // Yellow to red
        }
    }

    /// Get color map as texture data (256 RGBA values)
    pub fn to_texture_data(&self) -> Vec<u8> {
        let mut data = Vec::with_capacity(256 * 4);
        for i in 0..256 {
            let t = i as f32 / 255.0;
            let [r, g, b, a] = self.sample(t);
            data.push((r * 255.0) as u8);
            data.push((g * 255.0) as u8);
            data.push((b * 255.0) as u8);
            data.push((a * 255.0) as u8);
        }
        data
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPECTROGRAM CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Frequency scale type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum FrequencyScale {
    /// Linear frequency scale
    Linear,
    /// Logarithmic frequency scale (default, musical)
    #[default]
    Logarithmic,
    /// Mel scale (perceptual)
    Mel,
    /// Bark scale (critical bands)
    Bark,
}

/// Display mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum DisplayMode {
    /// 2D heatmap
    #[default]
    Heatmap,
    /// 3D waterfall (time on Z axis)
    Waterfall3D,
    /// 3D mountain view
    Mountain3D,
    /// Lollipop/peaks view
    Peaks,
}

/// Spectrogram configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpectrogramConfig {
    /// FFT size (power of 2)
    pub fft_size: usize,
    /// Hop size (overlap = fft_size - hop_size)
    pub hop_size: usize,
    /// Window function
    pub window: WindowFunction,
    /// Color map
    pub color_map: ColorMap,
    /// Frequency scale
    pub frequency_scale: FrequencyScale,
    /// Display mode
    pub display_mode: DisplayMode,
    /// Minimum frequency (Hz)
    pub min_freq: f32,
    /// Maximum frequency (Hz)
    pub max_freq: f32,
    /// Minimum dB level for display
    pub min_db: f32,
    /// Maximum dB level for display
    pub max_db: f32,
    /// Peak hold (frames)
    pub peak_hold: u32,
    /// Smoothing factor (0.0-1.0)
    pub smoothing: f32,
    /// History length (frames for 3D view)
    pub history_frames: usize,
    /// 3D rotation angle X (degrees)
    pub rotation_x: f32,
    /// 3D rotation angle Y (degrees)
    pub rotation_y: f32,
    /// 3D extrusion depth
    pub depth_3d: f32,
}

impl Default for SpectrogramConfig {
    fn default() -> Self {
        Self {
            fft_size: 4096,
            hop_size: 1024,
            window: WindowFunction::Hann,
            color_map: ColorMap::Viridis,
            frequency_scale: FrequencyScale::Logarithmic,
            display_mode: DisplayMode::Heatmap,
            min_freq: 20.0,
            max_freq: 20000.0,
            min_db: -90.0,
            max_db: 0.0,
            peak_hold: 30,
            smoothing: 0.3,
            history_frames: 100,
            rotation_x: 60.0,
            rotation_y: 45.0,
            depth_3d: 0.5,
        }
    }
}

/// Window function for FFT
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum WindowFunction {
    /// Rectangular (no window)
    Rectangular,
    /// Hann window (default)
    #[default]
    Hann,
    /// Hamming window
    Hamming,
    /// Blackman window
    Blackman,
    /// Blackman-Harris window
    BlackmanHarris,
    /// Kaiser window (beta=9)
    Kaiser,
    /// Flat-top window (amplitude accuracy)
    FlatTop,
}

impl WindowFunction {
    /// Generate window coefficients
    pub fn generate(&self, size: usize) -> Vec<f32> {
        let n = size as f32;
        (0..size)
            .map(|i| {
                let x = i as f32 / n;
                match self {
                    WindowFunction::Rectangular => 1.0,
                    WindowFunction::Hann => 0.5 * (1.0 - (2.0 * std::f32::consts::PI * x).cos()),
                    WindowFunction::Hamming => 0.54 - 0.46 * (2.0 * std::f32::consts::PI * x).cos(),
                    WindowFunction::Blackman => {
                        0.42 - 0.5 * (2.0 * std::f32::consts::PI * x).cos()
                            + 0.08 * (4.0 * std::f32::consts::PI * x).cos()
                    }
                    WindowFunction::BlackmanHarris => {
                        let a0 = 0.35875;
                        let a1 = 0.48829;
                        let a2 = 0.14128;
                        let a3 = 0.01168;
                        a0 - a1 * (2.0 * std::f32::consts::PI * x).cos()
                            + a2 * (4.0 * std::f32::consts::PI * x).cos()
                            - a3 * (6.0 * std::f32::consts::PI * x).cos()
                    }
                    WindowFunction::Kaiser => {
                        // Simplified Kaiser approximation
                        let alpha = 9.0 * 0.5;
                        let t = 2.0 * x - 1.0;
                        let arg = alpha * (1.0 - t * t).sqrt();
                        Self::bessel_i0(arg) / Self::bessel_i0(alpha)
                    }
                    WindowFunction::FlatTop => {
                        let a0 = 0.21557895;
                        let a1 = 0.41663158;
                        let a2 = 0.277_263_16;
                        let a3 = 0.083578947;
                        let a4 = 0.006947368;
                        a0 - a1 * (2.0 * std::f32::consts::PI * x).cos()
                            + a2 * (4.0 * std::f32::consts::PI * x).cos()
                            - a3 * (6.0 * std::f32::consts::PI * x).cos()
                            + a4 * (8.0 * std::f32::consts::PI * x).cos()
                    }
                }
            })
            .collect()
    }

    /// Modified Bessel function of first kind, order 0
    fn bessel_i0(x: f32) -> f32 {
        let mut sum = 1.0f32;
        let mut term = 1.0f32;
        for k in 1..20 {
            term *= (x / (2.0 * k as f32)).powi(2);
            sum += term;
        }
        sum
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPECTROGRAM DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Single spectrogram frame (one FFT result)
#[derive(Debug, Clone)]
pub struct SpectrogramFrame {
    /// Magnitude bins (dB normalized to 0.0-1.0)
    pub bins: Vec<f32>,
    /// Peak hold bins
    pub peaks: Vec<f32>,
    /// Time position (samples)
    pub position: u64,
}

impl SpectrogramFrame {
    /// Create empty frame
    pub fn new(num_bins: usize) -> Self {
        Self {
            bins: vec![0.0; num_bins],
            peaks: vec![0.0; num_bins],
            position: 0,
        }
    }
}

/// Spectrogram data buffer
#[derive(Debug)]
pub struct SpectrogramData {
    /// Configuration
    pub config: SpectrogramConfig,
    /// Window coefficients
    window: Vec<f32>,
    /// Frame history
    frames: Vec<SpectrogramFrame>,
    /// Current write position
    write_pos: usize,
    /// Number of bins (fft_size / 2 + 1)
    num_bins: usize,
    /// Sample rate
    sample_rate: f32,
    /// Peak decay counter
    peak_counters: Vec<u32>,
    /// Smoothed bins for display
    smoothed_bins: Vec<f32>,
}

impl SpectrogramData {
    /// Create new spectrogram data
    pub fn new(config: SpectrogramConfig, sample_rate: f32) -> Self {
        let num_bins = config.fft_size / 2 + 1;
        let window = config.window.generate(config.fft_size);

        let mut frames = Vec::with_capacity(config.history_frames);
        for _ in 0..config.history_frames {
            frames.push(SpectrogramFrame::new(num_bins));
        }

        Self {
            window,
            frames,
            write_pos: 0,
            num_bins,
            sample_rate,
            peak_counters: vec![0; num_bins],
            smoothed_bins: vec![0.0; num_bins],
            config,
        }
    }

    /// Process new FFT magnitudes and add frame
    pub fn add_frame(&mut self, magnitudes: &[f32], position: u64) {
        let frame = &mut self.frames[self.write_pos];
        frame.position = position;

        // Convert to dB and normalize
        for (i, &mag) in magnitudes.iter().take(self.num_bins).enumerate() {
            // Convert to dB
            let db = if mag > 0.0 {
                20.0 * mag.log10()
            } else {
                self.config.min_db
            };

            // Normalize to 0.0-1.0
            let normalized = (db - self.config.min_db) / (self.config.max_db - self.config.min_db);
            let normalized = normalized.clamp(0.0, 1.0);

            // Apply smoothing
            self.smoothed_bins[i] = self.smoothed_bins[i] * self.config.smoothing
                + normalized * (1.0 - self.config.smoothing);

            frame.bins[i] = self.smoothed_bins[i];

            // Update peaks
            if normalized >= frame.peaks[i] {
                frame.peaks[i] = normalized;
                self.peak_counters[i] = 0;
            } else {
                self.peak_counters[i] += 1;
                if self.peak_counters[i] > self.config.peak_hold {
                    frame.peaks[i] *= 0.95; // Decay
                }
            }
        }

        self.write_pos = (self.write_pos + 1) % self.frames.len();
    }

    /// Get frames in chronological order (oldest first)
    pub fn get_frames(&self) -> impl Iterator<Item = &SpectrogramFrame> {
        let len = self.frames.len();
        (0..len).map(move |i| {
            let idx = (self.write_pos + i) % len;
            &self.frames[idx]
        })
    }

    /// Get latest frame
    pub fn latest_frame(&self) -> &SpectrogramFrame {
        let idx = if self.write_pos == 0 {
            self.frames.len() - 1
        } else {
            self.write_pos - 1
        };
        &self.frames[idx]
    }

    /// Get frequency for bin index
    pub fn bin_to_frequency(&self, bin: usize) -> f32 {
        bin as f32 * self.sample_rate / self.config.fft_size as f32
    }

    /// Get bin index for frequency
    pub fn frequency_to_bin(&self, freq: f32) -> usize {
        ((freq * self.config.fft_size as f32 / self.sample_rate) as usize).min(self.num_bins - 1)
    }

    /// Map frequency to display position (0.0-1.0) based on scale
    pub fn frequency_to_position(&self, freq: f32) -> f32 {
        let min = self.config.min_freq;
        let max = self.config.max_freq;

        match self.config.frequency_scale {
            FrequencyScale::Linear => (freq - min) / (max - min),
            FrequencyScale::Logarithmic => (freq.ln() - min.ln()) / (max.ln() - min.ln()),
            FrequencyScale::Mel => {
                let to_mel = |f: f32| 2595.0 * (1.0 + f / 700.0).log10();
                (to_mel(freq) - to_mel(min)) / (to_mel(max) - to_mel(min))
            }
            FrequencyScale::Bark => {
                let to_bark = |f: f32| {
                    13.0 * (f / 1000.0 * 0.76).atan() + 3.5 * ((f / 7500.0).powi(2)).atan()
                };
                (to_bark(freq) - to_bark(min)) / (to_bark(max) - to_bark(min))
            }
        }
    }

    /// Get number of bins
    pub fn num_bins(&self) -> usize {
        self.num_bins
    }

    /// Get window coefficients
    pub fn window(&self) -> &[f32] {
        &self.window
    }

    /// Reset all data
    pub fn clear(&mut self) {
        for frame in &mut self.frames {
            frame.bins.fill(0.0);
            frame.peaks.fill(0.0);
        }
        self.smoothed_bins.fill(0.0);
        self.peak_counters.fill(0);
    }

    /// Set color map
    pub fn set_color_map(&mut self, color_map: ColorMap) {
        self.config.color_map = color_map;
    }

    /// Set display mode
    pub fn set_display_mode(&mut self, mode: DisplayMode) {
        self.config.display_mode = mode;
    }

    /// Set frequency scale
    pub fn set_frequency_scale(&mut self, scale: FrequencyScale) {
        self.config.frequency_scale = scale;
    }

    /// Set dB range
    pub fn set_db_range(&mut self, min_db: f32, max_db: f32) {
        self.config.min_db = min_db;
        self.config.max_db = max_db;
    }

    /// Set 3D rotation
    pub fn set_rotation(&mut self, x: f32, y: f32) {
        self.config.rotation_x = x;
        self.config.rotation_y = y;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3D VERTEX DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Vertex for 3D spectrogram rendering
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct SpectrogramVertex {
    /// Position (x, y, z)
    pub position: [f32; 3],
    /// Color (r, g, b, a)
    pub color: [f32; 4],
    /// Texture coordinates (u, v) - for color map lookup
    pub uv: [f32; 2],
}

impl SpectrogramVertex {
    /// Create vertex at position with intensity
    pub fn new(x: f32, y: f32, z: f32, intensity: f32, color_map: &ColorMap) -> Self {
        let color = color_map.sample(intensity);
        Self {
            position: [x, y, z],
            color,
            uv: [intensity, 0.0],
        }
    }
}

/// Generate 3D mesh for spectrogram
pub fn generate_3d_mesh(
    data: &SpectrogramData,
    width: f32,
    height: f32,
    depth: f32,
) -> (Vec<SpectrogramVertex>, Vec<u32>) {
    let frames: Vec<&SpectrogramFrame> = data.get_frames().collect();
    let num_frames = frames.len();
    let num_bins = data.num_bins();

    if num_frames == 0 || num_bins == 0 {
        return (Vec::new(), Vec::new());
    }

    let mut vertices = Vec::with_capacity(num_frames * num_bins);
    let mut indices = Vec::with_capacity((num_frames - 1) * (num_bins - 1) * 6);

    let frame_step = depth / num_frames as f32;
    let bin_step = width / num_bins as f32;

    // Generate vertices
    for (frame_idx, frame) in frames.iter().enumerate() {
        let z = frame_idx as f32 * frame_step;

        for (bin_idx, &intensity) in frame.bins.iter().enumerate() {
            let x = bin_idx as f32 * bin_step;
            let y = intensity * height;

            vertices.push(SpectrogramVertex::new(
                x - width * 0.5,
                y,
                z - depth * 0.5,
                intensity,
                &data.config.color_map,
            ));
        }
    }

    // Generate indices for triangle mesh
    for frame_idx in 0..(num_frames - 1) {
        for bin_idx in 0..(num_bins - 1) {
            let base = (frame_idx * num_bins + bin_idx) as u32;
            let next_frame = ((frame_idx + 1) * num_bins + bin_idx) as u32;

            // Two triangles per quad
            indices.push(base);
            indices.push(base + 1);
            indices.push(next_frame);

            indices.push(base + 1);
            indices.push(next_frame + 1);
            indices.push(next_frame);
        }
    }

    (vertices, indices)
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_color_map_sample() {
        let map = ColorMap::Viridis;
        let [r, g, b, a] = map.sample(0.5);
        assert!(r >= 0.0 && r <= 1.0);
        assert!(g >= 0.0 && g <= 1.0);
        assert!(b >= 0.0 && b <= 1.0);
        assert_eq!(a, 1.0);
    }

    #[test]
    fn test_window_function() {
        let window = WindowFunction::Hann.generate(1024);
        assert_eq!(window.len(), 1024);

        // Hann window should start and end near 0
        assert!(window[0] < 0.01);
        assert!(window[1023] < 0.01);

        // Peak at center
        assert!(window[512] > 0.9);
    }

    #[test]
    fn test_spectrogram_data() {
        let config = SpectrogramConfig::default();
        let mut data = SpectrogramData::new(config, 48000.0);

        // Add a frame
        let magnitudes: Vec<f32> = (0..2049).map(|i| i as f32 / 2048.0).collect();
        data.add_frame(&magnitudes, 0);

        let frame = data.latest_frame();
        assert!(!frame.bins.is_empty());
    }

    #[test]
    fn test_frequency_to_bin() {
        let config = SpectrogramConfig::default();
        let data = SpectrogramData::new(config, 48000.0);

        // 1000Hz at 48kHz with 4096 FFT should be bin ~85
        let bin = data.frequency_to_bin(1000.0);
        assert!(bin > 80 && bin < 90);
    }

    #[test]
    fn test_3d_mesh_generation() {
        let config = SpectrogramConfig {
            history_frames: 10,
            fft_size: 256,
            ..Default::default()
        };
        let data = SpectrogramData::new(config, 48000.0);

        let (vertices, indices) = generate_3d_mesh(&data, 1.0, 1.0, 1.0);

        // Should have vertices for all frames * bins
        let expected_vertices = 10 * 129; // 10 frames, 256/2+1 bins
        assert_eq!(vertices.len(), expected_vertices);

        // Should have indices for (frames-1) * (bins-1) * 6
        let expected_indices = 9 * 128 * 6;
        assert_eq!(indices.len(), expected_indices);
    }
}
