//! Ambisonic decoder - Ambisonic to speaker layout

use crate::position::Position3D;
use crate::error::{SpatialError, SpatialResult};
use crate::{SpeakerLayout, Speaker};
use super::{AmbisonicOrder, SphericalHarmonics};
use ndarray::Array2;

/// Decoding method
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecodingMethod {
    /// Basic (projection)
    Basic,
    /// Sampling decoder
    Sampling,
    /// Mode matching
    ModeMatching,
    /// All-round Ambisonic decoder (AllRAD)
    AllRAD,
    /// Energy preserving
    EnergyPreserving,
}

/// Ambisonic decoder to speaker layout
pub struct AmbisonicDecoder {
    /// Ambisonic order
    order: AmbisonicOrder,
    /// Number of input channels
    num_input_channels: usize,
    /// Output speaker layout
    layout: SpeakerLayout,
    /// Decoding matrix [speakers x ambisonic_channels]
    decode_matrix: Array2<f32>,
    /// Decoding method
    method: DecodingMethod,
    /// Near-field compensation enabled
    nfc: bool,
    /// Near-field compensation filters state
    nfc_state: Vec<Vec<f32>>,
}

impl AmbisonicDecoder {
    /// Create new decoder
    pub fn new(order: AmbisonicOrder, layout: SpeakerLayout) -> SpatialResult<Self> {
        let num_input_channels = order.channel_count();
        let _num_speakers = layout.speakers.iter().filter(|s| !s.is_lfe).count();

        // Create basic decoding matrix
        let decode_matrix = Self::create_decode_matrix(order, &layout, DecodingMethod::Basic)?;

        Ok(Self {
            order,
            num_input_channels,
            layout,
            decode_matrix,
            method: DecodingMethod::Basic,
            nfc: false,
            nfc_state: Vec::new(),
        })
    }

    /// Create decoder with specific method
    pub fn with_method(
        order: AmbisonicOrder,
        layout: SpeakerLayout,
        method: DecodingMethod,
    ) -> SpatialResult<Self> {
        let num_input_channels = order.channel_count();
        let decode_matrix = Self::create_decode_matrix(order, &layout, method)?;

        Ok(Self {
            order,
            num_input_channels,
            layout,
            decode_matrix,
            method,
            nfc: false,
            nfc_state: Vec::new(),
        })
    }

    /// Enable near-field compensation
    pub fn set_nfc(&mut self, enabled: bool) {
        self.nfc = enabled;
        if enabled {
            // Initialize NFC filter states
            let num_speakers = self.layout.speakers.iter().filter(|s| !s.is_lfe).count();
            self.nfc_state = vec![vec![0.0; self.order.as_usize()]; num_speakers];
        }
    }

    /// Get output layout
    pub fn output_layout(&self) -> &SpeakerLayout {
        &self.layout
    }

    /// Decode Ambisonic signal to speaker feeds
    pub fn decode(&self, ambisonic: &[Vec<f32>]) -> SpatialResult<Vec<Vec<f32>>> {
        if ambisonic.len() < self.num_input_channels {
            return Err(SpatialError::InvalidChannelCount {
                expected: self.num_input_channels,
                got: ambisonic.len(),
            });
        }

        let samples = ambisonic[0].len();
        let num_speakers = self.decode_matrix.nrows();
        let mut output = vec![vec![0.0f32; samples]; num_speakers];

        // Matrix multiply: output = decode_matrix * input
        for s in 0..samples {
            for spk in 0..num_speakers {
                let mut sum = 0.0f32;
                for ch in 0..self.num_input_channels {
                    sum += self.decode_matrix[[spk, ch]] * ambisonic[ch][s];
                }
                output[spk][s] = sum;
            }
        }

        Ok(output)
    }

    /// Decode with LFE management
    pub fn decode_with_lfe(
        &self,
        ambisonic: &[Vec<f32>],
        lfe_crossover_hz: f32,
        sample_rate: u32,
    ) -> SpatialResult<Vec<Vec<f32>>> {
        let speaker_output = self.decode(ambisonic)?;
        let samples = ambisonic[0].len();
        let total_channels = self.layout.total_channels();

        let mut output = vec![vec![0.0f32; samples]; total_channels];

        // Copy speaker outputs
        let mut spk_idx = 0;
        for speaker in &self.layout.speakers {
            if speaker.is_lfe {
                // Extract low frequencies from W channel
                output[speaker.channel] = Self::lowpass(
                    &ambisonic[0],
                    lfe_crossover_hz,
                    sample_rate,
                );
            } else {
                output[speaker.channel] = speaker_output[spk_idx].clone();
                spk_idx += 1;
            }
        }

        Ok(output)
    }

    /// Create decoding matrix
    fn create_decode_matrix(
        order: AmbisonicOrder,
        layout: &SpeakerLayout,
        method: DecodingMethod,
    ) -> SpatialResult<Array2<f32>> {
        let num_channels = order.channel_count();
        let speakers: Vec<&Speaker> = layout.speakers.iter().filter(|s| !s.is_lfe).collect();
        let num_speakers = speakers.len();

        if num_speakers == 0 {
            return Err(SpatialError::InvalidLayout("No speakers defined".into()));
        }

        let mut matrix = Array2::<f32>::zeros((num_speakers, num_channels));

        match method {
            DecodingMethod::Basic | DecodingMethod::Sampling => {
                // Basic/sampling decoder: transpose of encoding matrix
                for (spk_idx, speaker) in speakers.iter().enumerate() {
                    let spherical = speaker.position.to_spherical();
                    let sh = SphericalHarmonics::from_direction(
                        spherical.azimuth,
                        spherical.elevation,
                        order,
                    );

                    for ch in 0..num_channels {
                        matrix[[spk_idx, ch]] = sh.get(ch);
                    }
                }

                // Normalize by speaker count for energy preservation
                let gain = 1.0 / (num_speakers as f32).sqrt();
                matrix *= gain;
            }

            DecodingMethod::ModeMatching => {
                // Mode matching decoder using pseudoinverse
                // E^T (E E^T)^-1
                // For simplicity, use basic decoder with order-dependent gains
                for (spk_idx, speaker) in speakers.iter().enumerate() {
                    let spherical = speaker.position.to_spherical();
                    let sh = SphericalHarmonics::from_direction(
                        spherical.azimuth,
                        spherical.elevation,
                        order,
                    );

                    for ch in 0..num_channels {
                        let (l, _m) = super::acn_to_order_degree(ch);
                        // Order-dependent gain
                        let order_gain = match l {
                            0 => 1.0,
                            1 => 1.0,
                            2 => 1.0 / 1.414,
                            3 => 1.0 / 1.732,
                            _ => 1.0 / (l as f32 + 1.0).sqrt(),
                        };
                        matrix[[spk_idx, ch]] = sh.get(ch) * order_gain;
                    }
                }

                let gain = 1.0 / (num_speakers as f32).sqrt();
                matrix *= gain;
            }

            DecodingMethod::AllRAD => {
                // AllRAD decoder - projection onto virtual speaker array
                // then VBAP-style panning
                Self::create_allrad_matrix(&mut matrix, &speakers, order)?;
            }

            DecodingMethod::EnergyPreserving => {
                // Energy preserving: normalize each speaker output
                for (spk_idx, speaker) in speakers.iter().enumerate() {
                    let spherical = speaker.position.to_spherical();
                    let sh = SphericalHarmonics::from_direction(
                        spherical.azimuth,
                        spherical.elevation,
                        order,
                    );

                    // Compute energy for this speaker
                    let mut energy = 0.0f32;
                    for ch in 0..num_channels {
                        energy += sh.get(ch) * sh.get(ch);
                    }
                    let norm = if energy > 0.0 { 1.0 / energy.sqrt() } else { 1.0 };

                    for ch in 0..num_channels {
                        matrix[[spk_idx, ch]] = sh.get(ch) * norm;
                    }
                }

                let gain = 1.0 / (num_speakers as f32).sqrt();
                matrix *= gain;
            }
        }

        Ok(matrix)
    }

    /// Create AllRAD decoding matrix
    fn create_allrad_matrix(
        matrix: &mut Array2<f32>,
        speakers: &[&Speaker],
        order: AmbisonicOrder,
    ) -> SpatialResult<()> {
        let _num_speakers = speakers.len();
        let num_channels = order.channel_count();

        // Create virtual speaker positions on a t-design
        let virtual_speakers = Self::create_tdesign(2 * order.as_usize() + 1);

        // For each virtual speaker, find VBAP gains to real speakers
        for (_v_idx, v_pos) in virtual_speakers.iter().enumerate() {
            let vbap_gains = Self::compute_vbap_gains(v_pos, speakers);

            // Compute SH coefficients for virtual speaker
            let sh = SphericalHarmonics::from_direction(
                v_pos.to_spherical().azimuth,
                v_pos.to_spherical().elevation,
                order,
            );

            // Accumulate to decoding matrix
            for (spk_idx, &gain) in vbap_gains.iter().enumerate() {
                for ch in 0..num_channels {
                    matrix[[spk_idx, ch]] += sh.get(ch) * gain / virtual_speakers.len() as f32;
                }
            }
        }

        Ok(())
    }

    /// Create t-design points on sphere
    fn create_tdesign(t: usize) -> Vec<Position3D> {
        // Simplified t-design using Fibonacci spiral
        let n = ((t + 1) * (t + 1)) as usize;
        let mut points = Vec::with_capacity(n);

        let golden_ratio = (1.0 + 5.0_f32.sqrt()) / 2.0;

        for i in 0..n {
            let theta = 2.0 * std::f32::consts::PI * i as f32 / golden_ratio;
            let phi = (1.0 - 2.0 * (i as f32 + 0.5) / n as f32).acos();

            let x = phi.sin() * theta.cos();
            let y = phi.sin() * theta.sin();
            let z = phi.cos();

            points.push(Position3D::new(x, y, z));
        }

        points
    }

    /// Compute VBAP gains for position
    fn compute_vbap_gains(position: &Position3D, speakers: &[&Speaker]) -> Vec<f32> {
        let num_speakers = speakers.len();
        let mut gains = vec![0.0f32; num_speakers];

        // Simplified VBAP: find nearest speaker and neighbors
        let mut min_dist = f32::MAX;
        let mut nearest_idx = 0;

        for (i, spk) in speakers.iter().enumerate() {
            let dist = position.distance_to(&spk.position);
            if dist < min_dist {
                min_dist = dist;
                nearest_idx = i;
            }
        }

        // Simple panning to nearest speaker
        // Full VBAP would use triangulation
        gains[nearest_idx] = 1.0;

        // Normalize
        let sum: f32 = gains.iter().map(|g| g * g).sum::<f32>().sqrt();
        if sum > 0.0 {
            for g in &mut gains {
                *g /= sum;
            }
        }

        gains
    }

    /// Simple lowpass filter for LFE
    fn lowpass(input: &[f32], cutoff_hz: f32, sample_rate: u32) -> Vec<f32> {
        let rc = 1.0 / (2.0 * std::f32::consts::PI * cutoff_hz);
        let dt = 1.0 / sample_rate as f32;
        let alpha = dt / (rc + dt);

        let mut output = vec![0.0f32; input.len()];
        let mut prev = 0.0f32;

        for (i, &sample) in input.iter().enumerate() {
            prev = prev + alpha * (sample - prev);
            output[i] = prev;
        }

        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decoder_creation() {
        let decoder = AmbisonicDecoder::new(
            AmbisonicOrder::First,
            SpeakerLayout::stereo(),
        ).unwrap();

        assert_eq!(decoder.output_layout().total_channels(), 2);
    }

    #[test]
    fn test_decode_stereo() {
        let decoder = AmbisonicDecoder::new(
            AmbisonicOrder::First,
            SpeakerLayout::stereo(),
        ).unwrap();

        // First order Ambisonic: W, Y, Z, X
        let ambisonic = vec![
            vec![1.0; 100], // W (omni)
            vec![0.0; 100], // Y (left/right - center)
            vec![0.0; 100], // Z (up/down)
            vec![1.0; 100], // X (front/back)
        ];

        let decoded = decoder.decode(&ambisonic).unwrap();

        assert_eq!(decoded.len(), 2);
        // Both speakers should receive similar signal (front center source)
        assert!((decoded[0][0] - decoded[1][0]).abs() < 0.1);
    }

    #[test]
    fn test_decode_5_1() {
        let decoder = AmbisonicDecoder::new(
            AmbisonicOrder::First,
            SpeakerLayout::surround_5_1(),
        ).unwrap();

        // Source on left (negative Y)
        let ambisonic = vec![
            vec![1.0; 100], // W
            vec![-1.0; 100], // Y (left)
            vec![0.0; 100], // Z
            vec![0.0; 100], // X
        ];

        let decoded = decoder.decode(&ambisonic).unwrap();

        // L should be louder than R
        assert!(decoded[0][0].abs() > decoded[1][0].abs() * 1.5);
    }
}
