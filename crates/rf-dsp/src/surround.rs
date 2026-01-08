//! Surround & Immersive Audio Panning
//!
//! Professional multichannel panning for:
//! - 5.1 Surround (L, R, C, LFE, Ls, Rs)
//! - 7.1 Surround (adds Lss, Rss or Lrs, Rrs)
//! - Dolby Atmos / Object-based (beds + objects with XYZ position)
//! - Ambisonics (1st/2nd/3rd order)
//!
//! Pan laws:
//! - VBAP (Vector Base Amplitude Panning)
//! - DBAP (Distance-Based Amplitude Panning)
//! - Ambisonics encoding

use rf_core::Sample;
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL LAYOUTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Standard channel layouts
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ChannelLayout {
    #[default]
    Stereo,
    Surround51,      // L R C LFE Ls Rs
    Surround71,      // L R C LFE Ls Rs Lrs Rrs
    Surround714,     // 7.1.4 Atmos base (adds 4 ceiling)
    Surround916,     // 9.1.6 Atmos extended
    AmbisonicsFOA,   // 1st order (4 channels: W, X, Y, Z)
    AmbisonicsSOA,   // 2nd order (9 channels)
    AmbisonicsTOA,   // 3rd order (16 channels)
}

impl ChannelLayout {
    /// Get number of channels for this layout
    pub fn channel_count(&self) -> usize {
        match self {
            Self::Stereo => 2,
            Self::Surround51 => 6,
            Self::Surround71 => 8,
            Self::Surround714 => 12,
            Self::Surround916 => 16,
            Self::AmbisonicsFOA => 4,
            Self::AmbisonicsSOA => 9,
            Self::AmbisonicsTOA => 16,
        }
    }

    /// Get speaker positions in degrees (azimuth, elevation)
    pub fn speaker_positions(&self) -> Vec<(f64, f64)> {
        match self {
            Self::Stereo => vec![(-30.0, 0.0), (30.0, 0.0)],
            Self::Surround51 => vec![
                (-30.0, 0.0),   // L
                (30.0, 0.0),    // R
                (0.0, 0.0),     // C
                (0.0, -90.0),   // LFE (below, virtual position)
                (-110.0, 0.0),  // Ls
                (110.0, 0.0),   // Rs
            ],
            Self::Surround71 => vec![
                (-30.0, 0.0),   // L
                (30.0, 0.0),    // R
                (0.0, 0.0),     // C
                (0.0, -90.0),   // LFE
                (-90.0, 0.0),   // Lss (side surround)
                (90.0, 0.0),    // Rss
                (-150.0, 0.0),  // Lrs (rear surround)
                (150.0, 0.0),   // Rrs
            ],
            Self::Surround714 => vec![
                // Bed layer (7.1)
                (-30.0, 0.0), (30.0, 0.0), (0.0, 0.0), (0.0, -90.0),
                (-90.0, 0.0), (90.0, 0.0), (-150.0, 0.0), (150.0, 0.0),
                // Height layer (4 ceiling)
                (-45.0, 45.0), (45.0, 45.0), (-135.0, 45.0), (135.0, 45.0),
            ],
            Self::Surround916 => vec![
                // Bed layer
                (-30.0, 0.0), (30.0, 0.0), (0.0, 0.0), (0.0, -90.0),
                (-60.0, 0.0), (60.0, 0.0), (-90.0, 0.0), (90.0, 0.0),
                (-150.0, 0.0), (150.0, 0.0),
                // Height layer (6 ceiling)
                (-30.0, 45.0), (30.0, 45.0), (-90.0, 45.0), (90.0, 45.0),
                (-150.0, 45.0), (150.0, 45.0),
            ],
            _ => vec![], // Ambisonics uses virtual speakers
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3D POSITION
// ═══════════════════════════════════════════════════════════════════════════════

/// 3D position for object-based panning
#[derive(Debug, Clone, Copy, Default)]
pub struct Position3D {
    /// X position (-1.0 = left, 1.0 = right)
    pub x: f64,
    /// Y position (-1.0 = back, 1.0 = front)
    pub y: f64,
    /// Z position (-1.0 = floor, 1.0 = ceiling)
    pub z: f64,
}

impl Position3D {
    pub fn new(x: f64, y: f64, z: f64) -> Self {
        Self { x, y, z }
    }

    /// Create from spherical coordinates (azimuth, elevation, distance)
    pub fn from_spherical(azimuth_deg: f64, elevation_deg: f64, distance: f64) -> Self {
        let az = azimuth_deg * PI / 180.0;
        let el = elevation_deg * PI / 180.0;

        Self {
            x: distance * el.cos() * az.sin(),
            y: distance * el.cos() * az.cos(),
            z: distance * el.sin(),
        }
    }

    /// Convert to spherical (azimuth, elevation, distance)
    pub fn to_spherical(&self) -> (f64, f64, f64) {
        let distance = (self.x * self.x + self.y * self.y + self.z * self.z).sqrt();
        if distance < 1e-10 {
            return (0.0, 0.0, 0.0);
        }

        let azimuth = self.x.atan2(self.y) * 180.0 / PI;
        let elevation = (self.z / distance).asin() * 180.0 / PI;

        (azimuth, elevation, distance)
    }

    /// Distance from origin
    pub fn distance(&self) -> f64 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }

    /// Normalize to unit sphere
    pub fn normalize(&self) -> Self {
        let d = self.distance();
        if d < 1e-10 {
            return Self::new(0.0, 1.0, 0.0); // Default to front
        }
        Self::new(self.x / d, self.y / d, self.z / d)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SURROUND PANNER
// ═══════════════════════════════════════════════════════════════════════════════

/// Surround panner using VBAP (Vector Base Amplitude Panning)
pub struct SurroundPanner {
    layout: ChannelLayout,
    position: Position3D,
    spread: f64,           // 0.0 = point source, 1.0 = omnidirectional
    lfe_level: f64,        // 0.0-1.0, how much goes to LFE
    distance: f64,         // 0.0-1.0, affects attenuation
    gains: Vec<f64>,       // Per-speaker gains
    speaker_positions: Vec<Position3D>, // Normalized speaker positions
}

impl SurroundPanner {
    pub fn new(layout: ChannelLayout) -> Self {
        let speaker_positions: Vec<Position3D> = layout
            .speaker_positions()
            .iter()
            .map(|&(az, el)| Position3D::from_spherical(az, el, 1.0))
            .collect();

        let channel_count = layout.channel_count();

        let mut panner = Self {
            layout,
            position: Position3D::new(0.0, 1.0, 0.0), // Front center
            spread: 0.0,
            lfe_level: 0.0,
            distance: 1.0,
            gains: vec![0.0; channel_count],
            speaker_positions,
        };

        panner.update_gains();
        panner
    }

    /// Set pan position
    pub fn set_position(&mut self, pos: Position3D) {
        self.position = pos.normalize();
        self.update_gains();
    }

    /// Set position from azimuth and elevation in degrees
    pub fn set_position_spherical(&mut self, azimuth: f64, elevation: f64) {
        self.position = Position3D::from_spherical(azimuth, elevation, 1.0);
        self.update_gains();
    }

    /// Set spread (0.0 = point, 1.0 = omnidirectional)
    pub fn set_spread(&mut self, spread: f64) {
        self.spread = spread.clamp(0.0, 1.0);
        self.update_gains();
    }

    /// Set LFE contribution level
    pub fn set_lfe_level(&mut self, level: f64) {
        self.lfe_level = level.clamp(0.0, 1.0);
        self.update_gains();
    }

    /// Set distance (affects attenuation)
    pub fn set_distance(&mut self, distance: f64) {
        self.distance = distance.clamp(0.0, 2.0);
        self.update_gains();
    }

    /// Get current gains for all speakers
    pub fn gains(&self) -> &[f64] {
        &self.gains
    }

    /// Calculate VBAP gains
    fn update_gains(&mut self) {
        let num_speakers = self.speaker_positions.len();
        if num_speakers == 0 {
            return;
        }

        // Calculate dot products (cosine of angle between source and each speaker)
        let mut dots: Vec<f64> = self.speaker_positions
            .iter()
            .map(|spk| {
                self.position.x * spk.x + self.position.y * spk.y + self.position.z * spk.z
            })
            .collect();

        // Apply spread: blend between focused (VBAP) and diffuse (equal power)
        if self.spread > 0.0 {
            let equal_power = 1.0 / (num_speakers as f64).sqrt();
            for dot in &mut dots {
                *dot = *dot * (1.0 - self.spread) + equal_power * self.spread;
            }
        }

        // Convert dot products to gains using cosine pan law
        let mut total_power = 0.0;
        for (i, dot) in dots.iter().enumerate() {
            // Map dot product (-1 to 1) to gain (0 to 1)
            let gain = if *dot > 0.0 {
                // Front hemisphere - use dot product directly
                *dot
            } else {
                // Rear hemisphere - attenuate more
                0.0
            };

            self.gains[i] = gain;
            total_power += gain * gain;
        }

        // Normalize to constant power
        if total_power > 1e-10 {
            let scale = 1.0 / total_power.sqrt();
            for gain in &mut self.gains {
                *gain *= scale;
            }
        }

        // Apply distance attenuation
        if self.distance > 1.0 {
            let attenuation = 1.0 / self.distance;
            for gain in &mut self.gains {
                *gain *= attenuation;
            }
        }

        // Handle LFE channel specially (index 3 in 5.1/7.1)
        if matches!(self.layout, ChannelLayout::Surround51 | ChannelLayout::Surround71 |
                    ChannelLayout::Surround714 | ChannelLayout::Surround916) {
            // LFE gets a bass-managed send, not VBAP
            self.gains[3] = self.lfe_level;
        }
    }

    /// Process mono input to surround output
    pub fn process_mono(&self, input: Sample, output: &mut [Sample]) {
        for (i, gain) in self.gains.iter().enumerate() {
            if i < output.len() {
                output[i] = input * (*gain);
            }
        }
    }

    /// Process stereo input to surround output (preserves stereo width)
    pub fn process_stereo(&self, left: Sample, right: Sample, output: &mut [Sample]) {
        // Blend stereo image with panning
        let mono = (left + right) * 0.5;
        let side = (left - right) * 0.5;

        for (i, &gain) in self.gains.iter().enumerate() {
            if i >= output.len() {
                break;
            }

            // Get speaker position to determine L/R contribution
            if i < self.speaker_positions.len() {
                let spk = &self.speaker_positions[i];
                // Negative X = left speaker, positive X = right speaker
                let stereo_blend = -spk.x.clamp(-1.0, 1.0) * 0.5;
                output[i] = (mono + side * stereo_blend) * gain;
            } else {
                output[i] = mono * gain;
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AMBISONICS ENCODER
// ═══════════════════════════════════════════════════════════════════════════════

/// First-order Ambisonics encoder
pub struct AmbisonicsEncoder {
    azimuth: f64,    // Radians
    elevation: f64,  // Radians
    gain: f64,
}

impl AmbisonicsEncoder {
    pub fn new() -> Self {
        Self {
            azimuth: 0.0,
            elevation: 0.0,
            gain: 1.0,
        }
    }

    /// Set position in degrees
    pub fn set_position(&mut self, azimuth_deg: f64, elevation_deg: f64) {
        self.azimuth = azimuth_deg * PI / 180.0;
        self.elevation = elevation_deg * PI / 180.0;
    }

    /// Set gain
    pub fn set_gain(&mut self, gain: f64) {
        self.gain = gain.clamp(0.0, 2.0);
    }

    /// Encode mono input to B-format (W, X, Y, Z)
    pub fn encode_foa(&self, input: Sample) -> [Sample; 4] {
        let cos_el = self.elevation.cos();
        let sin_el = self.elevation.sin();
        let cos_az = self.azimuth.cos();
        let sin_az = self.azimuth.sin();

        let s = input * self.gain;

        [
            s * 0.707,                    // W (omnidirectional)
            s * cos_el * cos_az,          // X (front-back)
            s * cos_el * sin_az,          // Y (left-right)
            s * sin_el,                   // Z (up-down)
        ]
    }

    /// Encode to 2nd order ambisonics (9 channels)
    pub fn encode_soa(&self, input: Sample) -> [Sample; 9] {
        let cos_el = self.elevation.cos();
        let sin_el = self.elevation.sin();
        let cos_az = self.azimuth.cos();
        let sin_az = self.azimuth.sin();
        let cos_2az = (2.0 * self.azimuth).cos();
        let sin_2az = (2.0 * self.azimuth).sin();
        let cos_el_sq = cos_el * cos_el;

        let s = input * self.gain;

        [
            // 0th order
            s * 0.707,                                    // W
            // 1st order
            s * cos_el * cos_az,                          // X
            s * cos_el * sin_az,                          // Y
            s * sin_el,                                   // Z
            // 2nd order
            s * cos_el_sq * cos_2az,                      // R
            s * cos_el * sin_el * cos_az,                 // S
            s * cos_el * sin_el * sin_az,                 // T
            s * cos_el_sq * sin_2az,                      // U
            s * (3.0 * sin_el * sin_el - 1.0) * 0.5,      // V
        ]
    }
}

impl Default for AmbisonicsEncoder {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AMBISONICS DECODER
// ═══════════════════════════════════════════════════════════════════════════════

/// Ambisonics decoder to speaker array
pub struct AmbisonicsDecoder {
    layout: ChannelLayout,
    decode_matrix: Vec<Vec<f64>>,
}

impl AmbisonicsDecoder {
    pub fn new(layout: ChannelLayout) -> Self {
        let decode_matrix = Self::calculate_decode_matrix(&layout);

        Self {
            layout,
            decode_matrix,
        }
    }

    /// Calculate decode matrix for given speaker layout
    fn calculate_decode_matrix(layout: &ChannelLayout) -> Vec<Vec<f64>> {
        let positions = layout.speaker_positions();
        let _num_speakers = positions.len();

        // For each speaker, calculate its B-format coefficients
        positions.iter().map(|&(az, el)| {
            let az_rad = az * PI / 180.0;
            let el_rad = el * PI / 180.0;
            let cos_el = el_rad.cos();
            let sin_el = el_rad.sin();
            let cos_az = az_rad.cos();
            let sin_az = az_rad.sin();

            // FOA decode coefficients
            vec![
                1.0,                        // W
                cos_el * cos_az,            // X
                cos_el * sin_az,            // Y
                sin_el,                     // Z
            ]
        }).collect()
    }

    /// Decode B-format to speaker feeds
    pub fn decode_foa(&self, w: Sample, x: Sample, y: Sample, z: Sample) -> Vec<Sample> {
        let b_format = [w, x, y, z];

        self.decode_matrix.iter().map(|coeffs| {
            coeffs.iter().zip(&b_format)
                .map(|(&c, &b)| c * b)
                .sum()
        }).collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ATMOS OBJECT
// ═══════════════════════════════════════════════════════════════════════════════

/// Dolby Atmos-style audio object
#[derive(Debug, Clone)]
pub struct AtmosObject {
    /// Unique object ID
    pub id: u32,
    /// Object name
    pub name: String,
    /// Current position
    pub position: Position3D,
    /// Size/spread (0.0 = point, 1.0 = full room)
    pub size: f64,
    /// Gain in dB
    pub gain_db: f64,
    /// Is object enabled
    pub enabled: bool,
    /// Snap to nearest speaker (bed mode)
    pub snap_to_bed: bool,
}

impl AtmosObject {
    pub fn new(id: u32, name: &str) -> Self {
        Self {
            id,
            name: name.to_string(),
            position: Position3D::new(0.0, 1.0, 0.0),
            size: 0.0,
            gain_db: 0.0,
            enabled: true,
            snap_to_bed: false,
        }
    }

    /// Get linear gain
    pub fn gain(&self) -> f64 {
        10.0_f64.powf(self.gain_db / 20.0)
    }

    /// Set position from XYZ (-1 to 1)
    pub fn set_position(&mut self, x: f64, y: f64, z: f64) {
        self.position = Position3D::new(
            x.clamp(-1.0, 1.0),
            y.clamp(-1.0, 1.0),
            z.clamp(-1.0, 1.0),
        );
    }
}

/// Atmos bed renderer
pub struct AtmosRenderer {
    layout: ChannelLayout,
    objects: Vec<AtmosObject>,
    panners: Vec<SurroundPanner>,
    output_buffer: Vec<Vec<Sample>>,
    block_size: usize,
}

impl AtmosRenderer {
    pub fn new(layout: ChannelLayout, block_size: usize) -> Self {
        let channel_count = layout.channel_count();

        Self {
            layout,
            objects: Vec::new(),
            panners: Vec::new(),
            output_buffer: vec![vec![0.0; block_size]; channel_count],
            block_size,
        }
    }

    /// Add an audio object
    pub fn add_object(&mut self, object: AtmosObject) -> usize {
        let idx = self.objects.len();
        self.objects.push(object);

        // Create corresponding panner
        let mut panner = SurroundPanner::new(self.layout);
        panner.set_position(self.objects[idx].position);
        panner.set_spread(self.objects[idx].size);
        self.panners.push(panner);

        idx
    }

    /// Update object position
    pub fn update_object(&mut self, id: u32, position: Position3D, size: f64) {
        if let Some(idx) = self.objects.iter().position(|o| o.id == id) {
            self.objects[idx].position = position;
            self.objects[idx].size = size;
            self.panners[idx].set_position(position);
            self.panners[idx].set_spread(size);
        }
    }

    /// Render all objects to output
    pub fn render(
        &mut self,
        object_inputs: &[(u32, &[Sample])], // (object_id, mono input)
    ) -> &[Vec<Sample>] {
        // Clear output buffer
        for ch in &mut self.output_buffer {
            ch.fill(0.0);
        }

        // Render each object
        for (object_id, input) in object_inputs {
            if let Some(idx) = self.objects.iter().position(|o| o.id == *object_id && o.enabled) {
                let object = &self.objects[idx];
                let panner = &self.panners[idx];
                let gain = object.gain();

                let mut speaker_out = vec![0.0; self.layout.channel_count()];

                for (sample_idx, &sample) in input.iter().enumerate() {
                    if sample_idx >= self.block_size {
                        break;
                    }

                    panner.process_mono(sample * gain, &mut speaker_out);

                    for (ch, &spk_sample) in speaker_out.iter().enumerate() {
                        if ch < self.output_buffer.len() {
                            self.output_buffer[ch][sample_idx] += spk_sample;
                        }
                    }
                }
            }
        }

        &self.output_buffer
    }

    /// Get all objects
    pub fn objects(&self) -> &[AtmosObject] {
        &self.objects
    }

    /// Get mutable object reference
    pub fn object_mut(&mut self, id: u32) -> Option<&mut AtmosObject> {
        self.objects.iter_mut().find(|o| o.id == id)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_position_spherical_conversion() {
        let pos = Position3D::from_spherical(45.0, 30.0, 1.0);
        let (az, el, dist) = pos.to_spherical();

        assert!((az - 45.0).abs() < 0.1);
        assert!((el - 30.0).abs() < 0.1);
        assert!((dist - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_surround_panner_front() {
        let panner = SurroundPanner::new(ChannelLayout::Surround51);

        // Front center should have gains mainly in center speaker
        let gains = panner.gains();

        // Channel 2 is center in 5.1
        assert!(gains[2] > gains[0]); // C > L
        assert!(gains[2] > gains[1]); // C > R
    }

    #[test]
    fn test_surround_panner_left() {
        let mut panner = SurroundPanner::new(ChannelLayout::Surround51);
        panner.set_position_spherical(-30.0, 0.0);

        let gains = panner.gains();

        // Left speaker should be dominant
        assert!(gains[0] > gains[1]); // L > R
        assert!(gains[0] > gains[2]); // L > C
    }

    #[test]
    fn test_ambisonics_encoder() {
        let mut encoder = AmbisonicsEncoder::new();
        encoder.set_position(0.0, 0.0); // Front center

        let [w, x, y, z] = encoder.encode_foa(1.0);

        // Front center should have positive X, zero Y
        assert!(x > 0.9);
        assert!(y.abs() < 0.01);
        assert!(z.abs() < 0.01);
    }

    #[test]
    fn test_channel_layout_count() {
        assert_eq!(ChannelLayout::Stereo.channel_count(), 2);
        assert_eq!(ChannelLayout::Surround51.channel_count(), 6);
        assert_eq!(ChannelLayout::Surround71.channel_count(), 8);
        assert_eq!(ChannelLayout::Surround714.channel_count(), 12);
    }

    #[test]
    fn test_atmos_object() {
        let mut obj = AtmosObject::new(1, "Dialog");
        obj.set_position(0.0, 1.0, 0.0);

        assert!(obj.enabled);
        assert!((obj.gain() - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_position_normalize() {
        let pos = Position3D::new(3.0, 4.0, 0.0);
        let norm = pos.normalize();

        assert!((norm.distance() - 1.0).abs() < 0.01);
    }
}
