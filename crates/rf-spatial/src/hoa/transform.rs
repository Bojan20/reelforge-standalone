//! Ambisonic transformations - rotation, zoom, focus

use crate::position::Orientation;
use crate::error::SpatialResult;
use super::AmbisonicOrder;

/// Ambisonic transformation processor
pub struct AmbisonicTransform {
    /// Current order
    order: AmbisonicOrder,
    /// Rotation matrix
    rotation_matrix: Vec<Vec<f32>>,
    /// Current orientation
    orientation: Orientation,
    /// Dominance (focus) vector
    dominance: [f32; 3],
    /// Near-field distance
    near_field_distance: f32,
}

impl AmbisonicTransform {
    /// Create new transformer
    pub fn new(order: AmbisonicOrder) -> Self {
        let num_channels = order.channel_count();
        let rotation_matrix = vec![vec![0.0f32; num_channels]; num_channels];

        let mut transform = Self {
            order,
            rotation_matrix,
            orientation: Orientation::forward(),
            dominance: [0.0, 0.0, 0.0],
            near_field_distance: 0.0,
        };

        transform.update_rotation_matrix();
        transform
    }

    /// Set rotation
    pub fn set_rotation(&mut self, orientation: Orientation) {
        self.orientation = orientation;
        self.update_rotation_matrix();
    }

    /// Set dominance/focus direction
    pub fn set_dominance(&mut self, x: f32, y: f32, z: f32) {
        self.dominance = [x, y, z];
    }

    /// Set near-field distance for proximity effect
    pub fn set_near_field(&mut self, distance: f32) {
        self.near_field_distance = distance;
    }

    /// Apply transformation to Ambisonic signal
    pub fn transform(&self, input: &[Vec<f32>]) -> Vec<Vec<f32>> {
        let num_channels = self.order.channel_count();
        let samples = input[0].len();
        let mut output = vec![vec![0.0f32; samples]; num_channels];

        // Apply rotation matrix
        for s in 0..samples {
            for out_ch in 0..num_channels {
                let mut sum = 0.0f32;
                for in_ch in 0..num_channels.min(input.len()) {
                    sum += self.rotation_matrix[out_ch][in_ch] * input[in_ch][s];
                }
                output[out_ch][s] = sum;
            }
        }

        output
    }

    /// Apply rotation only (more efficient for just yaw)
    pub fn rotate_yaw(&self, input: &[Vec<f32>], yaw_deg: f32) -> Vec<Vec<f32>> {
        let samples = input[0].len();
        let num_channels = self.order.channel_count().min(input.len());
        let mut output = vec![vec![0.0f32; samples]; num_channels];

        let cos_yaw = yaw_deg.to_radians().cos();
        let sin_yaw = yaw_deg.to_radians().sin();

        for s in 0..samples {
            // W unchanged
            output[0][s] = input[0][s];

            if num_channels > 3 {
                // Rotate first order Y and X
                output[1][s] = input[1][s] * cos_yaw - input[3][s] * sin_yaw;
                output[2][s] = input[2][s]; // Z unchanged
                output[3][s] = input[1][s] * sin_yaw + input[3][s] * cos_yaw;
            }

            // Higher orders would need more complex rotation
            for ch in 4..num_channels {
                output[ch][s] = input[ch][s];
            }
        }

        output
    }

    /// Apply mirror transformation (flip left/right)
    pub fn mirror_lr(&self, input: &[Vec<f32>]) -> Vec<Vec<f32>> {
        let mut output = input.to_vec();

        // Negate Y component (and all Y-derived channels)
        if output.len() > 1 {
            for s in &mut output[1] {
                *s = -*s;
            }
        }

        // Second order: negate V (4) and T (5)
        if output.len() > 4 {
            for s in &mut output[4] {
                *s = -*s;
            }
        }
        if output.len() > 5 {
            for s in &mut output[5] {
                *s = -*s;
            }
        }

        output
    }

    /// Apply shelf filter (frequency-dependent directivity)
    pub fn apply_shelf(
        &self,
        input: &[Vec<f32>],
        shelf_db: f32,
        high_order_cutoff_hz: f32,
        sample_rate: u32,
    ) -> Vec<Vec<f32>> {
        let mut output = input.to_vec();
        let shelf_gain = 10.0_f32.powf(shelf_db / 20.0);

        // Simple shelf: apply gain to higher-order channels
        // Full implementation would use proper shelf filter
        for ch in 4..output.len() {
            for s in &mut output[ch] {
                *s *= shelf_gain;
            }
        }

        output
    }

    /// Update rotation matrix from orientation
    fn update_rotation_matrix(&mut self) {
        let num_channels = self.order.channel_count();

        // Initialize to identity
        for i in 0..num_channels {
            for j in 0..num_channels {
                self.rotation_matrix[i][j] = if i == j { 1.0 } else { 0.0 };
            }
        }

        let rot = self.orientation.rotation_matrix();

        // Order 0: W is invariant
        // Already identity

        if num_channels >= 4 {
            // Order 1: 3D rotation
            // ACN order: Y(1), Z(2), X(3)
            // Our rotation matrix is for X, Y, Z order
            // Need to remap: Y->1, Z->2, X->3 means input[Y]=rot*[Y,Z,X]

            // Simplified: just apply 3x3 rotation to channels 1-3
            // Full implementation would use Wigner-D matrices
            self.rotation_matrix[1][1] = rot[1][1]; // Y -> Y
            self.rotation_matrix[1][2] = rot[1][2]; // Z -> Y
            self.rotation_matrix[1][3] = rot[1][0]; // X -> Y
            self.rotation_matrix[2][1] = rot[2][1]; // Y -> Z
            self.rotation_matrix[2][2] = rot[2][2]; // Z -> Z
            self.rotation_matrix[2][3] = rot[2][0]; // X -> Z
            self.rotation_matrix[3][1] = rot[0][1]; // Y -> X
            self.rotation_matrix[3][2] = rot[0][2]; // Z -> X
            self.rotation_matrix[3][3] = rot[0][0]; // X -> X
        }

        // Higher orders would require Wigner-D rotation matrices
        // This is a simplification
    }
}

/// Real-time rotation with interpolation
pub struct RotationInterpolator {
    /// Transform processor
    transform: AmbisonicTransform,
    /// Target orientation
    target: Orientation,
    /// Current orientation
    current: Orientation,
    /// Interpolation time (samples)
    interp_samples: usize,
    /// Current sample in interpolation
    interp_pos: usize,
}

impl RotationInterpolator {
    /// Create new interpolator
    pub fn new(order: AmbisonicOrder, interp_time_ms: f32, sample_rate: u32) -> Self {
        Self {
            transform: AmbisonicTransform::new(order),
            target: Orientation::forward(),
            current: Orientation::forward(),
            interp_samples: (interp_time_ms * sample_rate as f32 / 1000.0) as usize,
            interp_pos: 0,
        }
    }

    /// Set target orientation
    pub fn set_target(&mut self, orientation: Orientation) {
        self.target = orientation;
        self.interp_pos = 0;
    }

    /// Process block with interpolated rotation
    pub fn process(&mut self, input: &[Vec<f32>]) -> Vec<Vec<f32>> {
        let samples = input[0].len();

        if self.interp_pos >= self.interp_samples {
            // No interpolation needed
            self.transform.set_rotation(self.target);
            return self.transform.transform(input);
        }

        // Sample-by-sample interpolation
        let num_channels = input.len();
        let mut output = vec![vec![0.0f32; samples]; num_channels];

        for s in 0..samples {
            let t = if self.interp_samples > 0 {
                (self.interp_pos + s) as f32 / self.interp_samples as f32
            } else {
                1.0
            }.min(1.0);

            // Interpolate orientation
            let interp_orient = Orientation::new(
                self.current.yaw + (self.target.yaw - self.current.yaw) * t,
                self.current.pitch + (self.target.pitch - self.current.pitch) * t,
                self.current.roll + (self.target.roll - self.current.roll) * t,
            );

            self.transform.set_rotation(interp_orient);

            // Transform single sample
            for ch in 0..num_channels {
                let mut sum = 0.0f32;
                for in_ch in 0..num_channels {
                    sum += self.transform.rotation_matrix[ch][in_ch] * input[in_ch][s];
                }
                output[ch][s] = sum;
            }
        }

        self.interp_pos += samples;
        if self.interp_pos >= self.interp_samples {
            self.current = self.target;
        }

        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identity_transform() {
        let transform = AmbisonicTransform::new(AmbisonicOrder::First);

        let input = vec![
            vec![1.0; 10], // W
            vec![0.5; 10], // Y
            vec![0.3; 10], // Z
            vec![0.7; 10], // X
        ];

        let output = transform.transform(&input);

        // With identity rotation, output should match input
        for ch in 0..4 {
            for s in 0..10 {
                assert!((output[ch][s] - input[ch][s]).abs() < 0.001);
            }
        }
    }

    #[test]
    fn test_yaw_rotation() {
        let transform = AmbisonicTransform::new(AmbisonicOrder::First);

        // Source at front (X positive in ACN = channel 3)
        let input = vec![
            vec![1.0; 10], // W (channel 0)
            vec![0.0; 10], // Y (channel 1)
            vec![0.0; 10], // Z (channel 2)
            vec![1.0; 10], // X (channel 3)
        ];

        // Rotate 90 degrees - X and Y will be mixed
        let output = transform.rotate_yaw(&input, 90.0);

        // After rotation, original X becomes Y (or -Y depending on convention)
        // The important thing is that energy moved from X to Y
        let x_energy = output[3][0].abs();
        let y_energy = output[1][0].abs();

        // Y should now have significant energy (was X)
        assert!(y_energy > 0.5, "Y energy after rotation: {}", y_energy);
        // X should be much smaller
        assert!(x_energy < y_energy, "X: {}, Y: {}", x_energy, y_energy);
    }

    #[test]
    fn test_mirror() {
        let transform = AmbisonicTransform::new(AmbisonicOrder::First);

        let input = vec![
            vec![1.0; 10],  // W
            vec![0.5; 10],  // Y (left)
            vec![0.0; 10],  // Z
            vec![1.0; 10],  // X
        ];

        let mirrored = transform.mirror_lr(&input);

        // Y should be negated
        assert!((mirrored[1][0] - (-0.5)).abs() < 0.001);
    }
}
