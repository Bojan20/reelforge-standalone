//! EQ Spectrum Analyzer - GPU Accelerated
//!
//! Pro-Q style spectrum display with:
//! - Real-time FFT visualization
//! - EQ curve overlay
//! - Band handles
//! - Collision zones
//! - Peak hold
//! - Piano roll overlay

use std::f32::consts::PI;

// ============================================================================
// CONFIGURATION
// ============================================================================

/// Spectrum analyzer configuration
#[derive(Debug, Clone)]
pub struct EqSpectrumConfig {
    /// Number of spectrum bins to display
    pub num_bins: usize,
    /// Minimum frequency (Hz)
    pub min_freq: f32,
    /// Maximum frequency (Hz)
    pub max_freq: f32,
    /// Minimum dB
    pub min_db: f32,
    /// Maximum dB
    pub max_db: f32,
    /// Spectrum color (RGBA)
    pub spectrum_color: [f32; 4],
    /// EQ curve color
    pub curve_color: [f32; 4],
    /// Peak hold color
    pub peak_color: [f32; 4],
    /// Grid color
    pub grid_color: [f32; 4],
    /// Background color
    pub background_color: [f32; 4],
    /// Show grid
    pub show_grid: bool,
    /// Show piano roll
    pub show_piano_roll: bool,
    /// Show peak hold
    pub show_peak_hold: bool,
    /// Spectrum fill opacity
    pub fill_opacity: f32,
    /// Spectrum line width
    pub line_width: f32,
}

impl Default for EqSpectrumConfig {
    fn default() -> Self {
        Self {
            num_bins: 256,
            min_freq: 20.0,
            max_freq: 20000.0,
            min_db: -90.0,
            max_db: 6.0,
            spectrum_color: [0.29, 0.78, 1.0, 0.8],    // Cyan
            curve_color: [1.0, 0.56, 0.25, 1.0],       // Orange
            peak_color: [1.0, 0.25, 0.37, 0.6],        // Red
            grid_color: [0.3, 0.3, 0.35, 0.3],         // Gray
            background_color: [0.04, 0.04, 0.05, 1.0], // Dark
            show_grid: true,
            show_piano_roll: false,
            show_peak_hold: true,
            fill_opacity: 0.3,
            line_width: 2.0,
        }
    }
}

// ============================================================================
// BAND HANDLE
// ============================================================================

/// EQ band handle for interaction
#[derive(Debug, Clone, Copy)]
pub struct BandHandle {
    /// Band index
    pub index: usize,
    /// Frequency (Hz)
    pub frequency: f32,
    /// Gain (dB)
    pub gain_db: f32,
    /// Q factor
    pub q: f32,
    /// Is enabled
    pub enabled: bool,
    /// Is selected
    pub selected: bool,
    /// Is hovered
    pub hovered: bool,
    /// Handle color
    pub color: [f32; 4],
}

/// Collision zone (frequency masking)
#[derive(Debug, Clone, Copy)]
pub struct CollisionZone {
    /// Start frequency
    pub start_freq: f32,
    /// End frequency
    pub end_freq: f32,
    /// Severity (0-1)
    pub severity: f32,
}

// ============================================================================
// SPECTRUM DATA
// ============================================================================

/// Spectrum data for GPU upload
#[derive(Debug, Clone)]
pub struct EqSpectrumData {
    /// Spectrum magnitudes (0-1, normalized)
    pub spectrum: Vec<f32>,
    /// Peak hold magnitudes
    pub peaks: Vec<f32>,
    /// EQ curve (dB values)
    pub eq_curve: Vec<f32>,
    /// Band handles
    pub bands: Vec<BandHandle>,
    /// Collision zones
    pub collisions: Vec<CollisionZone>,
    /// Sample rate (for frequency calculation)
    pub sample_rate: f32,
}

impl Default for EqSpectrumData {
    fn default() -> Self {
        Self {
            spectrum: vec![0.0; 256],
            peaks: vec![0.0; 256],
            eq_curve: vec![0.0; 256],
            bands: Vec::new(),
            collisions: Vec::new(),
            sample_rate: 48000.0,
        }
    }
}

// ============================================================================
// VERTICES
// ============================================================================

/// Vertex for spectrum rendering
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct SpectrumVertex {
    /// Position (x, y)
    pub position: [f32; 2],
    /// UV coordinates
    pub uv: [f32; 2],
    /// Color (RGBA)
    pub color: [f32; 4],
}

impl SpectrumVertex {
    pub fn new(x: f32, y: f32, u: f32, v: f32, color: [f32; 4]) -> Self {
        Self {
            position: [x, y],
            uv: [u, v],
            color,
        }
    }
}

// ============================================================================
// MESH GENERATION
// ============================================================================

/// Generate spectrum mesh (filled area under curve)
pub fn generate_spectrum_mesh(
    data: &EqSpectrumData,
    config: &EqSpectrumConfig,
    width: f32,
    height: f32,
) -> (Vec<SpectrumVertex>, Vec<u32>) {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    let num_points = data.spectrum.len();
    if num_points < 2 {
        return (vertices, indices);
    }

    let _log_min = config.min_freq.log10();
    let _log_max = config.max_freq.log10();
    let db_range = config.max_db - config.min_db;

    // Generate filled spectrum
    for i in 0..num_points {
        let t = i as f32 / (num_points - 1) as f32;

        // Log-scale X position
        let x = t * width;

        // Spectrum magnitude to Y
        let mag = data.spectrum[i].clamp(0.0, 1.0);
        let db = config.min_db + mag * db_range;
        let y = height * (1.0 - (db - config.min_db) / db_range);

        // Top vertex (spectrum line)
        let mut color = config.spectrum_color;
        vertices.push(SpectrumVertex::new(x, y, t, mag, color));

        // Bottom vertex (baseline)
        color[3] *= config.fill_opacity;
        vertices.push(SpectrumVertex::new(x, height, t, 0.0, color));

        // Triangles for filled area
        if i > 0 {
            let base = (i as u32 - 1) * 2;
            indices.push(base);
            indices.push(base + 1);
            indices.push(base + 2);
            indices.push(base + 1);
            indices.push(base + 3);
            indices.push(base + 2);
        }
    }

    (vertices, indices)
}

/// Generate EQ curve mesh (line)
pub fn generate_curve_mesh(
    data: &EqSpectrumData,
    config: &EqSpectrumConfig,
    width: f32,
    height: f32,
) -> (Vec<SpectrumVertex>, Vec<u32>) {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    let num_points = data.eq_curve.len();
    if num_points < 2 {
        return (vertices, indices);
    }

    let db_range = config.max_db - config.min_db;
    let half_width = config.line_width * 0.5;

    for i in 0..num_points {
        let t = i as f32 / (num_points - 1) as f32;
        let x = t * width;

        // EQ curve dB to Y
        let db = data.eq_curve[i].clamp(config.min_db, config.max_db);
        let y = height * (1.0 - (db - config.min_db) / db_range);

        // Calculate normal for line thickness
        let (nx, ny) = if i == 0 {
            let next_t = (i + 1) as f32 / (num_points - 1) as f32;
            let next_x = next_t * width;
            let next_db = data.eq_curve[i + 1].clamp(config.min_db, config.max_db);
            let next_y = height * (1.0 - (next_db - config.min_db) / db_range);
            let dx = next_x - x;
            let dy = next_y - y;
            let len = (dx * dx + dy * dy).sqrt();
            (-dy / len, dx / len)
        } else if i == num_points - 1 {
            let prev_t = (i - 1) as f32 / (num_points - 1) as f32;
            let prev_x = prev_t * width;
            let prev_db = data.eq_curve[i - 1].clamp(config.min_db, config.max_db);
            let prev_y = height * (1.0 - (prev_db - config.min_db) / db_range);
            let dx = x - prev_x;
            let dy = y - prev_y;
            let len = (dx * dx + dy * dy).sqrt();
            (-dy / len, dx / len)
        } else {
            let prev_t = (i - 1) as f32 / (num_points - 1) as f32;
            let next_t = (i + 1) as f32 / (num_points - 1) as f32;
            let prev_x = prev_t * width;
            let next_x = next_t * width;
            let prev_db = data.eq_curve[i - 1].clamp(config.min_db, config.max_db);
            let next_db = data.eq_curve[i + 1].clamp(config.min_db, config.max_db);
            let prev_y = height * (1.0 - (prev_db - config.min_db) / db_range);
            let next_y = height * (1.0 - (next_db - config.min_db) / db_range);
            let dx = next_x - prev_x;
            let dy = next_y - prev_y;
            let len = (dx * dx + dy * dy).sqrt();
            (-dy / len, dx / len)
        };

        // Two vertices per point (for line thickness)
        vertices.push(SpectrumVertex::new(
            x + nx * half_width,
            y + ny * half_width,
            t,
            0.0,
            config.curve_color,
        ));
        vertices.push(SpectrumVertex::new(
            x - nx * half_width,
            y - ny * half_width,
            t,
            1.0,
            config.curve_color,
        ));

        if i > 0 {
            let base = (i as u32 - 1) * 2;
            indices.push(base);
            indices.push(base + 1);
            indices.push(base + 2);
            indices.push(base + 1);
            indices.push(base + 3);
            indices.push(base + 2);
        }
    }

    (vertices, indices)
}

/// Generate band handle circles
pub fn generate_band_handles(
    data: &EqSpectrumData,
    config: &EqSpectrumConfig,
    width: f32,
    height: f32,
) -> (Vec<SpectrumVertex>, Vec<u32>) {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    let log_min = config.min_freq.log10();
    let log_max = config.max_freq.log10();
    let db_range = config.max_db - config.min_db;

    for band in &data.bands {
        if !band.enabled {
            continue;
        }

        // Frequency to X (log scale)
        let log_freq = band.frequency.log10();
        let x = width * (log_freq - log_min) / (log_max - log_min);

        // Gain to Y
        let y = height * (1.0 - (band.gain_db - config.min_db) / db_range);

        // Circle radius based on selection state
        let radius = if band.selected {
            12.0
        } else if band.hovered {
            10.0
        } else {
            8.0
        };

        // Generate circle vertices
        let segments = 16;
        let base_idx = vertices.len() as u32;

        // Center vertex
        vertices.push(SpectrumVertex::new(x, y, 0.5, 0.5, band.color));

        // Circle vertices
        for i in 0..segments {
            let angle = 2.0 * PI * (i as f32) / (segments as f32);
            let px = x + angle.cos() * radius;
            let py = y + angle.sin() * radius;
            let u = 0.5 + angle.cos() * 0.5;
            let v = 0.5 + angle.sin() * 0.5;
            vertices.push(SpectrumVertex::new(px, py, u, v, band.color));
        }

        // Triangle fan indices
        for i in 0..segments {
            let next = (i + 1) % segments;
            indices.push(base_idx);
            indices.push(base_idx + 1 + i as u32);
            indices.push(base_idx + 1 + next as u32);
        }
    }

    (vertices, indices)
}

/// Generate grid lines
pub fn generate_grid(
    config: &EqSpectrumConfig,
    width: f32,
    height: f32,
) -> (Vec<SpectrumVertex>, Vec<u32>) {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    if !config.show_grid {
        return (vertices, indices);
    }

    let log_min = config.min_freq.log10();
    let log_max = config.max_freq.log10();
    let db_range = config.max_db - config.min_db;
    let line_width = 1.0;

    // Frequency grid lines (20, 50, 100, 200, 500, 1k, 2k, 5k, 10k, 20k)
    let freq_lines = [
        20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0,
    ];

    for &freq in &freq_lines {
        if freq < config.min_freq || freq > config.max_freq {
            continue;
        }

        let log_freq = freq.log10();
        let x = width * (log_freq - log_min) / (log_max - log_min);

        let base = vertices.len() as u32;
        vertices.push(SpectrumVertex::new(
            x - line_width * 0.5,
            0.0,
            0.0,
            0.0,
            config.grid_color,
        ));
        vertices.push(SpectrumVertex::new(
            x + line_width * 0.5,
            0.0,
            1.0,
            0.0,
            config.grid_color,
        ));
        vertices.push(SpectrumVertex::new(
            x + line_width * 0.5,
            height,
            1.0,
            1.0,
            config.grid_color,
        ));
        vertices.push(SpectrumVertex::new(
            x - line_width * 0.5,
            height,
            0.0,
            1.0,
            config.grid_color,
        ));

        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    // dB grid lines (every 6 dB)
    let mut db = config.min_db;
    while db <= config.max_db {
        let y = height * (1.0 - (db - config.min_db) / db_range);

        let base = vertices.len() as u32;
        vertices.push(SpectrumVertex::new(
            0.0,
            y - line_width * 0.5,
            0.0,
            0.0,
            config.grid_color,
        ));
        vertices.push(SpectrumVertex::new(
            width,
            y - line_width * 0.5,
            1.0,
            0.0,
            config.grid_color,
        ));
        vertices.push(SpectrumVertex::new(
            width,
            y + line_width * 0.5,
            1.0,
            1.0,
            config.grid_color,
        ));
        vertices.push(SpectrumVertex::new(
            0.0,
            y + line_width * 0.5,
            0.0,
            1.0,
            config.grid_color,
        ));

        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);

        db += 6.0;
    }

    (vertices, indices)
}

/// Generate piano roll overlay
pub fn generate_piano_roll(
    config: &EqSpectrumConfig,
    width: f32,
    height: f32,
) -> (Vec<SpectrumVertex>, Vec<u32>) {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    if !config.show_piano_roll {
        return (vertices, indices);
    }

    let log_min = config.min_freq.log10();
    let log_max = config.max_freq.log10();

    // Piano key frequencies (A0 to C8)
    let piano_height = 20.0;
    let y_top = height - piano_height;

    // Generate key for each MIDI note
    for midi in 21..=108 {
        let freq = 440.0 * 2.0_f32.powf((midi as f32 - 69.0) / 12.0);
        let next_freq = 440.0 * 2.0_f32.powf((midi as f32 + 1.0 - 69.0) / 12.0);

        if freq < config.min_freq || freq > config.max_freq {
            continue;
        }

        let log_freq = freq.log10();
        let log_next = next_freq.log10();
        let x1 = width * (log_freq - log_min) / (log_max - log_min);
        let x2 = width * (log_next - log_min) / (log_max - log_min);

        // Is black key?
        let note = midi % 12;
        let is_black = matches!(note, 1 | 3 | 6 | 8 | 10);

        let color = if is_black {
            [0.1, 0.1, 0.1, 0.8]
        } else {
            [0.9, 0.9, 0.9, 0.8]
        };

        let key_height = if is_black {
            piano_height * 0.6
        } else {
            piano_height
        };
        let y_bottom = y_top + key_height;

        let base = vertices.len() as u32;
        vertices.push(SpectrumVertex::new(x1, y_top, 0.0, 0.0, color));
        vertices.push(SpectrumVertex::new(x2, y_top, 1.0, 0.0, color));
        vertices.push(SpectrumVertex::new(x2, y_bottom, 1.0, 1.0, color));
        vertices.push(SpectrumVertex::new(x1, y_bottom, 0.0, 1.0, color));

        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    (vertices, indices)
}

/// Generate collision zone overlays
pub fn generate_collision_zones(
    data: &EqSpectrumData,
    config: &EqSpectrumConfig,
    width: f32,
    height: f32,
) -> (Vec<SpectrumVertex>, Vec<u32>) {
    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    let log_min = config.min_freq.log10();
    let log_max = config.max_freq.log10();

    for zone in &data.collisions {
        let x1 = width * (zone.start_freq.log10() - log_min) / (log_max - log_min);
        let x2 = width * (zone.end_freq.log10() - log_min) / (log_max - log_min);

        let alpha = zone.severity.clamp(0.0, 1.0) * 0.3;
        let color = [1.0, 0.3, 0.3, alpha]; // Red overlay

        let base = vertices.len() as u32;
        vertices.push(SpectrumVertex::new(x1, 0.0, 0.0, 0.0, color));
        vertices.push(SpectrumVertex::new(x2, 0.0, 1.0, 0.0, color));
        vertices.push(SpectrumVertex::new(x2, height, 1.0, 1.0, color));
        vertices.push(SpectrumVertex::new(x1, height, 0.0, 1.0, color));

        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    (vertices, indices)
}

// ============================================================================
// FREQUENCY HELPERS
// ============================================================================

/// Convert normalized X (0-1) to frequency (Hz)
pub fn x_to_frequency(x: f32, min_freq: f32, max_freq: f32) -> f32 {
    let log_min = min_freq.log10();
    let log_max = max_freq.log10();
    10.0_f32.powf(log_min + x * (log_max - log_min))
}

/// Convert frequency (Hz) to normalized X (0-1)
pub fn frequency_to_x(freq: f32, min_freq: f32, max_freq: f32) -> f32 {
    let log_min = min_freq.log10();
    let log_max = max_freq.log10();
    (freq.log10() - log_min) / (log_max - log_min)
}

/// Convert normalized Y (0-1) to dB
pub fn y_to_db(y: f32, min_db: f32, max_db: f32) -> f32 {
    max_db - y * (max_db - min_db)
}

/// Convert dB to normalized Y (0-1)
pub fn db_to_y(db: f32, min_db: f32, max_db: f32) -> f32 {
    (max_db - db) / (max_db - min_db)
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frequency_conversion() {
        let min = 20.0;
        let max = 20000.0;

        // 1000 Hz should be roughly in the middle on log scale
        let x = frequency_to_x(1000.0, min, max);
        assert!(x > 0.4 && x < 0.6);

        // Round trip
        let freq = x_to_frequency(x, min, max);
        assert!((freq - 1000.0).abs() < 1.0);
    }

    #[test]
    fn test_db_conversion() {
        let min_db = -90.0;
        let max_db = 6.0;

        // 0 dB should be near top
        let y = db_to_y(0.0, min_db, max_db);
        assert!(y < 0.1);

        // Round trip
        let db = y_to_db(y, min_db, max_db);
        assert!((db - 0.0).abs() < 0.1);
    }

    #[test]
    fn test_spectrum_mesh_generation() {
        let data = EqSpectrumData {
            spectrum: vec![0.5; 256],
            ..Default::default()
        };

        let config = EqSpectrumConfig::default();
        let (vertices, indices) = generate_spectrum_mesh(&data, &config, 800.0, 400.0);

        assert!(!vertices.is_empty());
        assert!(!indices.is_empty());
    }

    #[test]
    fn test_grid_generation() {
        let config = EqSpectrumConfig::default();
        let (vertices, indices) = generate_grid(&config, 800.0, 400.0);

        assert!(!vertices.is_empty());
        assert!(!indices.is_empty());
    }
}
