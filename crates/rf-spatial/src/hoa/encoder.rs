//! Ambisonic encoder - point source to Ambisonic

use super::{AmbisonicOrder, SphericalHarmonics};
use crate::position::Position3D;

/// Ambisonic encoder for point sources
pub struct AmbisonicEncoder {
    /// Ambisonic order
    order: AmbisonicOrder,
    /// Number of output channels
    num_channels: usize,
    /// Cached spherical harmonics for current position
    cached_sh: SphericalHarmonics,
    /// Last position (for cache validation)
    last_position: Option<Position3D>,
    /// Distance attenuation enabled
    distance_attenuation: bool,
    /// Reference distance for attenuation
    reference_distance: f32,
}

impl AmbisonicEncoder {
    /// Create new encoder with specified order
    pub fn new(order: AmbisonicOrder) -> Self {
        Self {
            order,
            num_channels: order.channel_count(),
            cached_sh: SphericalHarmonics::new(order),
            last_position: None,
            distance_attenuation: true,
            reference_distance: 1.0,
        }
    }

    /// Set distance attenuation
    pub fn set_distance_attenuation(&mut self, enabled: bool, reference_distance: f32) {
        self.distance_attenuation = enabled;
        self.reference_distance = reference_distance;
    }

    /// Get number of output channels
    pub fn channel_count(&self) -> usize {
        self.num_channels
    }

    /// Encode mono source at position
    pub fn encode(&mut self, mono: &[f32], position: &Position3D) -> Vec<Vec<f32>> {
        let samples = mono.len();
        let mut output = vec![vec![0.0f32; samples]; self.num_channels];

        // Update spherical harmonics if position changed
        self.update_position(position);

        // Compute distance gain
        let distance_gain = if self.distance_attenuation {
            let distance = position.magnitude();
            if distance > 0.0 {
                (self.reference_distance / distance).min(1.0)
            } else {
                1.0
            }
        } else {
            1.0
        };

        // Encode each sample
        for (i, &sample) in mono.iter().enumerate() {
            let scaled_sample = sample * distance_gain;
            for ch in 0..self.num_channels {
                output[ch][i] = scaled_sample * self.cached_sh.get(ch);
            }
        }

        output
    }

    /// Encode mono source with interpolated position
    pub fn encode_interpolated(
        &mut self,
        mono: &[f32],
        start_pos: &Position3D,
        end_pos: &Position3D,
    ) -> Vec<Vec<f32>> {
        let samples = mono.len();
        let mut output = vec![vec![0.0f32; samples]; self.num_channels];

        for (i, &sample) in mono.iter().enumerate() {
            // Interpolate position
            let t = i as f32 / samples.max(1) as f32;
            let pos = start_pos.lerp(end_pos, t);

            // Update spherical harmonics
            let spherical = pos.to_spherical();
            let sh = SphericalHarmonics::from_direction(
                spherical.azimuth,
                spherical.elevation,
                self.order,
            );

            // Distance gain
            let distance_gain = if self.distance_attenuation {
                let distance = pos.magnitude();
                if distance > 0.0 {
                    (self.reference_distance / distance).min(1.0)
                } else {
                    1.0
                }
            } else {
                1.0
            };

            let scaled_sample = sample * distance_gain;
            for ch in 0..self.num_channels {
                output[ch][i] = scaled_sample * sh.get(ch);
            }
        }

        output
    }

    /// Encode multiple sources
    pub fn encode_multiple(&mut self, sources: &[(&[f32], Position3D)]) -> Vec<Vec<f32>> {
        if sources.is_empty() {
            return vec![vec![]; self.num_channels];
        }

        let samples = sources[0].0.len();
        let mut output = vec![vec![0.0f32; samples]; self.num_channels];

        for (mono, position) in sources {
            let encoded = self.encode(mono, position);
            for ch in 0..self.num_channels {
                for i in 0..samples.min(encoded[ch].len()) {
                    output[ch][i] += encoded[ch][i];
                }
            }
        }

        output
    }

    /// Update cached spherical harmonics for position
    fn update_position(&mut self, position: &Position3D) {
        let needs_update = match &self.last_position {
            None => true,
            Some(last) => {
                (last.x - position.x).abs() > 1e-6
                    || (last.y - position.y).abs() > 1e-6
                    || (last.z - position.z).abs() > 1e-6
            }
        };

        if needs_update {
            let spherical = position.to_spherical();
            self.cached_sh
                .compute_for_direction(spherical.azimuth, spherical.elevation);
            self.last_position = Some(*position);
        }
    }
}

/// Multi-source encoder with object management
pub struct MultiSourceEncoder {
    /// Base encoder
    encoder: AmbisonicEncoder,
    /// Maximum number of sources
    max_sources: usize,
}

impl MultiSourceEncoder {
    /// Create new multi-source encoder
    pub fn new(order: AmbisonicOrder, max_sources: usize) -> Self {
        Self {
            encoder: AmbisonicEncoder::new(order),
            max_sources,
        }
    }

    /// Encode frame with multiple objects
    pub fn encode_frame(
        &mut self,
        sources: &[(&[f32], Position3D, f32)], // (audio, position, gain)
        output_samples: usize,
    ) -> Vec<Vec<f32>> {
        let num_channels = self.encoder.channel_count();
        let mut output = vec![vec![0.0f32; output_samples]; num_channels];

        for (audio, position, gain) in sources.iter().take(self.max_sources) {
            let encoded = self.encoder.encode(audio, position);
            for ch in 0..num_channels {
                for i in 0..output_samples.min(encoded[ch].len()) {
                    output[ch][i] += encoded[ch][i] * gain;
                }
            }
        }

        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encoder_creation() {
        let encoder = AmbisonicEncoder::new(AmbisonicOrder::First);
        assert_eq!(encoder.channel_count(), 4);

        let encoder = AmbisonicEncoder::new(AmbisonicOrder::Third);
        assert_eq!(encoder.channel_count(), 16);
    }

    #[test]
    fn test_encode_front() {
        let mut encoder = AmbisonicEncoder::new(AmbisonicOrder::First);
        let mono = vec![1.0f32; 100];
        let pos = Position3D::from_spherical(0.0, 0.0, 1.0); // Front

        let encoded = encoder.encode(&mono, &pos);

        assert_eq!(encoded.len(), 4);
        assert_eq!(encoded[0].len(), 100);

        // W should be constant
        assert!((encoded[0][0] - 1.0).abs() < 0.01);
        // X should be positive (front)
        assert!(encoded[3][0] > 0.9);
        // Y should be near zero (center)
        assert!(encoded[1][0].abs() < 0.01);
    }

    #[test]
    fn test_encode_left() {
        let mut encoder = AmbisonicEncoder::new(AmbisonicOrder::First);
        let mono = vec![1.0f32; 100];
        let pos = Position3D::from_spherical(-90.0, 0.0, 1.0); // Left

        let encoded = encoder.encode(&mono, &pos);

        // Y should be negative (left)
        assert!(encoded[1][0] < -0.9);
        // X should be near zero
        assert!(encoded[3][0].abs() < 0.01);
    }

    #[test]
    fn test_distance_attenuation() {
        let mut encoder = AmbisonicEncoder::new(AmbisonicOrder::First);
        encoder.set_distance_attenuation(true, 1.0);

        let mono = vec![1.0f32; 100];

        // Near source
        let near = encoder.encode(&mono, &Position3D::from_spherical(0.0, 0.0, 1.0));
        // Far source
        let far = encoder.encode(&mono, &Position3D::from_spherical(0.0, 0.0, 2.0));

        // Far should be quieter
        assert!(far[0][0].abs() < near[0][0].abs());
    }
}
