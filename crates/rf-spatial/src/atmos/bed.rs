//! Atmos bed (channel-based) mixing

use crate::error::SpatialResult;
use crate::SpeakerLayout;

/// Atmos bed configuration
#[derive(Debug, Clone)]
pub struct BedConfig {
    /// Input layout (e.g., 7.1)
    pub input_layout: SpeakerLayout,
    /// Output layout (e.g., 7.1.4)
    pub output_layout: SpeakerLayout,
    /// Enable upmixing to height
    pub upmix_height: bool,
    /// Height upmix amount
    pub height_amount: f32,
}

impl Default for BedConfig {
    fn default() -> Self {
        Self {
            input_layout: SpeakerLayout::surround_7_1(),
            output_layout: SpeakerLayout::atmos_7_1_4(),
            upmix_height: false,
            height_amount: 0.3,
        }
    }
}

/// Atmos bed mixer
pub struct AtmosBed {
    /// Configuration
    config: BedConfig,
    /// Routing matrix [output_channels x input_channels]
    routing: Vec<Vec<f32>>,
}

impl AtmosBed {
    /// Create new bed mixer
    pub fn new(config: BedConfig) -> Self {
        let routing = Self::create_routing(&config);
        Self { config, routing }
    }

    /// Create routing matrix
    fn create_routing(config: &BedConfig) -> Vec<Vec<f32>> {
        let in_ch = config.input_layout.total_channels();
        let out_ch = config.output_layout.total_channels();

        let mut routing = vec![vec![0.0f32; in_ch]; out_ch];

        // Direct routing for matching channels
        for (in_idx, in_spk) in config.input_layout.speakers.iter().enumerate() {
            for (out_idx, out_spk) in config.output_layout.speakers.iter().enumerate() {
                if in_spk.label == out_spk.label {
                    routing[out_idx][in_idx] = 1.0;
                }
            }
        }

        // Height upmix if enabled
        if config.upmix_height {
            // Find height speakers
            let height_indices: Vec<usize> = config.output_layout.speakers
                .iter()
                .enumerate()
                .filter(|(_, s)| s.position.z > 0.3)
                .map(|(i, _)| i)
                .collect();

            // Find corresponding bed speakers to upmix from
            for height_idx in &height_indices {
                let height_pos = &config.output_layout.speakers[*height_idx].position;

                // Find nearest bed speaker in horizontal plane
                let mut nearest_dist = f32::MAX;
                let mut nearest_idx = 0;

                for (in_idx, in_spk) in config.input_layout.speakers.iter().enumerate() {
                    if in_spk.is_lfe {
                        continue;
                    }

                    let dist = ((in_spk.position.x - height_pos.x).powi(2)
                        + (in_spk.position.y - height_pos.y).powi(2))
                        .sqrt();

                    if dist < nearest_dist {
                        nearest_dist = dist;
                        nearest_idx = in_idx;
                    }
                }

                // Route some signal to height
                routing[*height_idx][nearest_idx] = config.height_amount;
            }
        }

        routing
    }

    /// Process bed audio
    pub fn process(&self, input: &[Vec<f32>]) -> Vec<Vec<f32>> {
        let in_ch = self.config.input_layout.total_channels();
        let out_ch = self.config.output_layout.total_channels();
        let samples = input.get(0).map(|v| v.len()).unwrap_or(0);

        let mut output = vec![vec![0.0f32; samples]; out_ch];

        for s in 0..samples {
            for out_idx in 0..out_ch {
                let mut sum = 0.0f32;
                for in_idx in 0..in_ch.min(input.len()) {
                    sum += input[in_idx].get(s).copied().unwrap_or(0.0)
                        * self.routing[out_idx][in_idx];
                }
                output[out_idx][s] = sum;
            }
        }

        output
    }

    /// Get output layout
    pub fn output_layout(&self) -> &SpeakerLayout {
        &self.config.output_layout
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bed_creation() {
        let config = BedConfig::default();
        let bed = AtmosBed::new(config);
        assert_eq!(bed.output_layout().total_channels(), 12);
    }

    #[test]
    fn test_bed_routing() {
        let config = BedConfig::default();
        let bed = AtmosBed::new(config);

        // 8 input channels (7.1)
        let input = vec![vec![1.0f32; 100]; 8];
        let output = bed.process(&input);

        // Should have 12 output channels (7.1.4)
        assert_eq!(output.len(), 12);
    }
}
