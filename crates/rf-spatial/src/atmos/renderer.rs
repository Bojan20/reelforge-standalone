//! Atmos renderer

use super::AtmosObject;
use crate::error::SpatialResult;
use crate::position::{Orientation, Position3D};
use crate::{AudioObject, SpatialRenderer, SpeakerLayout};

/// Atmos rendering configuration
#[derive(Debug, Clone)]
pub struct AtmosConfig {
    /// Output speaker layout
    pub layout: SpeakerLayout,
    /// Maximum objects
    pub max_objects: usize,
    /// Enable binaural mode
    pub binaural: bool,
    /// Enable LFE management
    pub lfe_management: bool,
    /// LFE crossover frequency
    pub lfe_crossover_hz: f32,
    /// Room size for reverb
    pub room_size: f32,
}

impl Default for AtmosConfig {
    fn default() -> Self {
        Self {
            layout: SpeakerLayout::atmos_7_1_4(),
            max_objects: 128,
            binaural: false,
            lfe_management: true,
            lfe_crossover_hz: 80.0,
            room_size: 1.0,
        }
    }
}

/// Dolby Atmos renderer
pub struct AtmosRenderer {
    /// Configuration
    config: AtmosConfig,
    /// Sample rate
    sample_rate: u32,
    /// Object gain matrices (per object, per speaker)
    gain_matrices: Vec<Vec<f32>>,
    /// Previous gains for smoothing
    prev_gains: Vec<Vec<f32>>,
    /// LFE filter state
    lfe_state: Vec<f32>,
    /// Listener position
    listener_pos: Position3D,
    /// Listener orientation
    listener_orient: Orientation,
}

impl AtmosRenderer {
    /// Create new Atmos renderer
    pub fn new(config: AtmosConfig, sample_rate: u32) -> Self {
        let num_speakers = config.layout.total_channels();
        let max_obj = config.max_objects;

        Self {
            config: config.clone(),
            sample_rate,
            gain_matrices: vec![vec![0.0; num_speakers]; max_obj],
            prev_gains: vec![vec![0.0; num_speakers]; max_obj],
            lfe_state: vec![0.0; 4], // Biquad state
            listener_pos: Position3D::origin(),
            listener_orient: Orientation::forward(),
        }
    }

    /// Compute VBAP gains for position
    fn compute_vbap_gains(&self, position: &Position3D) -> Vec<f32> {
        let num_speakers = self.config.layout.total_channels();
        let mut gains = vec![0.0f32; num_speakers];

        // Convert to normalized coordinates (-1 to 1)
        let pos_norm = Position3D::new(
            position.x.clamp(-1.0, 1.0),
            position.y.clamp(-1.0, 1.0),
            position.z.clamp(0.0, 1.0),
        );

        // Find nearest speakers and compute gains
        for (idx, speaker) in self.config.layout.speakers.iter().enumerate() {
            if speaker.is_lfe {
                continue;
            }

            // Distance-based panning
            let dist = pos_norm.distance_to(&speaker.position);
            let gain = (1.0 - dist).max(0.0).powi(2);
            gains[idx] = gain;
        }

        // Normalize gains (equal power)
        let total: f32 = gains.iter().map(|g| g * g).sum::<f32>().sqrt();
        if total > 0.0 {
            for g in &mut gains {
                *g /= total;
            }
        }

        gains
    }

    /// Apply size/divergence to gains
    fn apply_divergence(&self, gains: &mut [f32], size: f32, divergence: f32) {
        if size <= 0.0 && divergence <= 0.0 {
            return;
        }

        let spread = size.max(divergence);
        let spread_factor = spread * 0.5;

        // Spread energy to adjacent speakers
        let original = gains.to_vec();
        for (idx, speaker) in self.config.layout.speakers.iter().enumerate() {
            if speaker.is_lfe {
                continue;
            }

            // Add contribution from neighbors
            let mut additional = 0.0f32;
            for (other_idx, other) in self.config.layout.speakers.iter().enumerate() {
                if other.is_lfe || other_idx == idx {
                    continue;
                }

                let dist = speaker.position.distance_to(&other.position);
                if dist < 1.0 {
                    additional += original[other_idx] * spread_factor * (1.0 - dist);
                }
            }

            gains[idx] = original[idx] * (1.0 - spread_factor) + additional;
        }

        // Renormalize
        let total: f32 = gains.iter().map(|g| g * g).sum::<f32>().sqrt();
        if total > 0.0 {
            for g in gains {
                *g /= total;
            }
        }
    }

    /// Process LFE (low frequency extraction)
    fn process_lfe(&mut self, input: f32) -> f32 {
        // Simple 2nd order lowpass at crossover frequency
        let fc = self.config.lfe_crossover_hz / self.sample_rate as f32;
        let omega = 2.0 * std::f32::consts::PI * fc;
        let alpha = omega.sin() / (2.0 * 0.707);

        let b0 = (1.0 - omega.cos()) / 2.0;
        let b1 = 1.0 - omega.cos();
        let b2 = b0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * omega.cos();
        let a2 = 1.0 - alpha;

        // Normalize
        let b0 = b0 / a0;
        let b1 = b1 / a0;
        let b2 = b2 / a0;
        let a1 = a1 / a0;
        let a2 = a2 / a0;

        // TDF-II biquad
        let output = b0 * input + self.lfe_state[0];
        self.lfe_state[0] = b1 * input - a1 * output + self.lfe_state[1];
        self.lfe_state[1] = b2 * input - a2 * output;

        output
    }

    /// Render Atmos objects to output
    pub fn render_objects(
        &mut self,
        objects: &[AtmosObject],
        audio: &[&[f32]],
        output: &mut [Vec<f32>],
    ) -> SpatialResult<()> {
        let _num_speakers = self.config.layout.total_channels();
        let samples = audio.first().map(|a| a.len()).unwrap_or(0);

        // Clear output
        for ch in output.iter_mut() {
            ch.fill(0.0);
        }

        // Process each object
        for (obj_idx, obj) in objects.iter().enumerate().take(self.config.max_objects) {
            let obj_audio = match audio.get(obj_idx) {
                Some(a) => *a,
                None => continue,
            };

            // Compute gains
            let mut gains = self.compute_vbap_gains(&obj.position);
            self.apply_divergence(&mut gains, obj.size, obj.divergence);

            // Apply object gain
            for g in &mut gains {
                *g *= obj.gain;
            }

            // Smooth gain transitions
            let smooth_factor = 0.99;
            for (idx, g) in gains.iter_mut().enumerate() {
                *g = self.prev_gains[obj_idx][idx] * smooth_factor + *g * (1.0 - smooth_factor);
                self.prev_gains[obj_idx][idx] = *g;
            }

            // Mix to outputs
            for s in 0..samples.min(obj_audio.len()) {
                let sample = obj_audio[s];

                for (spk_idx, &gain) in gains.iter().enumerate() {
                    if spk_idx < output.len() && s < output[spk_idx].len() {
                        output[spk_idx][s] += sample * gain;
                    }
                }

                // LFE management
                if self.config.lfe_management {
                    if let Some(lfe_idx) = self.config.layout.speakers.iter().position(|s| s.is_lfe)
                    {
                        let lfe_sample = self.process_lfe(sample);
                        if lfe_idx < output.len() && s < output[lfe_idx].len() {
                            output[lfe_idx][s] += lfe_sample * obj.gain * 0.707;
                        }
                    }
                }
            }
        }

        Ok(())
    }
}

impl SpatialRenderer for AtmosRenderer {
    fn render(
        &mut self,
        objects: &[AudioObject],
        output: &mut [f32],
        output_channels: usize,
    ) -> SpatialResult<()> {
        let samples = output.len() / output_channels;

        // Convert to Atmos objects
        let atmos_objects: Vec<AtmosObject> = objects
            .iter()
            .map(|o| AtmosObject {
                id: o.id,
                name: o.name.clone(),
                position: o.position,
                size: o.size,
                gain: o.gain,
                ..Default::default()
            })
            .collect();

        // Extract audio references
        let audio_refs: Vec<&[f32]> = objects.iter().map(|o| o.audio.as_slice()).collect();

        // Create output buffers
        let mut output_buffers: Vec<Vec<f32>> = (0..output_channels)
            .map(|_| vec![0.0f32; samples])
            .collect();

        // Render
        self.render_objects(&atmos_objects, &audio_refs, &mut output_buffers)?;

        // Interleave to output
        for s in 0..samples {
            for ch in 0..output_channels {
                output[s * output_channels + ch] = output_buffers[ch][s];
            }
        }

        Ok(())
    }

    fn output_layout(&self) -> &SpeakerLayout {
        &self.config.layout
    }

    fn set_listener_position(&mut self, position: Position3D, orientation: Orientation) {
        self.listener_pos = position;
        self.listener_orient = orientation;
    }

    fn latency_samples(&self) -> usize {
        0 // No inherent latency
    }

    fn reset(&mut self) {
        for gains in &mut self.prev_gains {
            gains.fill(0.0);
        }
        self.lfe_state.fill(0.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_atmos_renderer_creation() {
        let config = AtmosConfig::default();
        let renderer = AtmosRenderer::new(config, 48000);
        assert_eq!(renderer.config.max_objects, 128);
    }

    #[test]
    fn test_vbap_gains() {
        let config = AtmosConfig::default();
        let renderer = AtmosRenderer::new(config, 48000);

        // Center position should have front center as loudest
        let gains = renderer.compute_vbap_gains(&Position3D::new(0.0, 1.0, 0.0));

        // Some gain should be non-zero
        let total: f32 = gains.iter().sum();
        assert!(total > 0.0);
    }
}
