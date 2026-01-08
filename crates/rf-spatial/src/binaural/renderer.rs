//! Binaural renderer with HRTF convolution

use num_complex::Complex32;
use rustfft::{FftPlanner, Fft};
use std::sync::Arc;

use crate::error::{SpatialError, SpatialResult};
use crate::position::{Position3D, Orientation, SphericalCoord};
use crate::{AudioObject, SpatialRenderer, SpeakerLayout};
use super::{HrtfDatabase, HrirPair, Hrtf, Crossfeed};

/// Binaural rendering configuration
#[derive(Debug, Clone)]
pub struct BinauralConfig {
    /// FFT size for convolution (should be power of 2)
    pub fft_size: usize,
    /// Enable crossfeed for speaker simulation
    pub crossfeed: bool,
    /// Crossfeed amount (0-1)
    pub crossfeed_amount: f32,
    /// Enable head tracking
    pub head_tracking: bool,
    /// Enable near-field compensation
    pub near_field: bool,
    /// Near-field distance (meters)
    pub near_field_distance: f32,
    /// Maximum number of simultaneous sources
    pub max_sources: usize,
}

impl Default for BinauralConfig {
    fn default() -> Self {
        Self {
            fft_size: 1024,
            crossfeed: false,
            crossfeed_amount: 0.3,
            head_tracking: true,
            near_field: true,
            near_field_distance: 0.5,
            max_sources: 32,
        }
    }
}

/// Binaural renderer using HRTF convolution
pub struct BinauralRenderer {
    /// Configuration
    config: BinauralConfig,
    /// HRTF database
    hrtf_db: HrtfDatabase,
    /// Sample rate
    sample_rate: u32,
    /// FFT forward
    fft_forward: Arc<dyn Fft<f32>>,
    /// FFT inverse
    fft_inverse: Arc<dyn Fft<f32>>,
    /// Listener position
    listener_pos: Position3D,
    /// Listener orientation
    listener_orient: Orientation,
    /// Per-source convolution states
    source_states: Vec<SourceConvState>,
    /// Crossfeed processor
    crossfeed: Option<Crossfeed>,
    /// Output overlap-add buffer (left)
    overlap_left: Vec<f32>,
    /// Output overlap-add buffer (right)
    overlap_right: Vec<f32>,
    /// Current output position
    output_pos: usize,
}

/// Per-source convolution state
struct SourceConvState {
    /// Source ID
    source_id: u32,
    /// Input buffer
    input_buffer: Vec<f32>,
    /// Input position
    input_pos: usize,
    /// Previous HRTF (for interpolation)
    prev_hrtf: Option<Hrtf>,
    /// Current HRTF
    current_hrtf: Option<Hrtf>,
    /// Overlap-add buffer left
    overlap_left: Vec<f32>,
    /// Overlap-add buffer right
    overlap_right: Vec<f32>,
    /// Previous gain (for smoothing)
    prev_gain: f32,
}

impl SourceConvState {
    fn new(fft_size: usize) -> Self {
        Self {
            source_id: 0,
            input_buffer: vec![0.0; fft_size],
            input_pos: 0,
            prev_hrtf: None,
            current_hrtf: None,
            overlap_left: vec![0.0; fft_size],
            overlap_right: vec![0.0; fft_size],
            prev_gain: 0.0,
        }
    }

    fn reset(&mut self) {
        self.input_buffer.fill(0.0);
        self.input_pos = 0;
        self.prev_hrtf = None;
        self.current_hrtf = None;
        self.overlap_left.fill(0.0);
        self.overlap_right.fill(0.0);
        self.prev_gain = 0.0;
    }
}

impl BinauralRenderer {
    /// Create new binaural renderer
    pub fn new(config: BinauralConfig, sample_rate: u32) -> Self {
        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(config.fft_size);
        let fft_inverse = planner.plan_fft_inverse(config.fft_size);

        let hrtf_db = HrtfDatabase::default_synthetic(sample_rate);

        let crossfeed = if config.crossfeed {
            let mut cf = Crossfeed::new(sample_rate);
            cf.set_amount(config.crossfeed_amount);
            Some(cf)
        } else {
            None
        };

        let source_states = (0..config.max_sources)
            .map(|_| SourceConvState::new(config.fft_size))
            .collect();

        Self {
            config: config.clone(),
            hrtf_db,
            sample_rate,
            fft_forward,
            fft_inverse,
            listener_pos: Position3D::origin(),
            listener_orient: Orientation::forward(),
            source_states,
            crossfeed,
            overlap_left: vec![0.0; config.fft_size],
            overlap_right: vec![0.0; config.fft_size],
            output_pos: 0,
        }
    }

    /// Load custom HRTF database
    pub fn set_hrtf_database(&mut self, db: HrtfDatabase) {
        self.hrtf_db = db;
    }

    /// Process single source
    fn process_source(
        &self,
        state: &mut SourceConvState,
        audio: &[f32],
        position: &Position3D,
        gain: f32,
        output_left: &mut [f32],
        output_right: &mut [f32],
    ) {
        let fft_size = self.config.fft_size;
        let hop_size = fft_size / 2;

        // Transform position to listener-relative
        let relative_pos = if self.config.head_tracking {
            let world_rel = Position3D::new(
                position.x - self.listener_pos.x,
                position.y - self.listener_pos.y,
                position.z - self.listener_pos.z,
            );
            self.listener_orient.world_to_listener(&world_rel)
        } else {
            *position
        };

        let spherical = relative_pos.to_spherical();

        // Get HRTF for this direction
        let hrir = match self.hrtf_db.get_hrir(spherical.azimuth, spherical.elevation) {
            Some(h) => h,
            None => return,
        };

        let hrtf = Hrtf::from_hrir(&hrir, spherical, fft_size);

        // Distance attenuation
        let distance = relative_pos.magnitude();
        let distance_gain = if distance > 0.1 {
            (1.0 / distance).min(1.0)
        } else {
            1.0
        };

        let total_gain = gain * distance_gain;

        // Smooth gain changes
        let smooth_gain = state.prev_gain * 0.9 + total_gain * 0.1;
        state.prev_gain = smooth_gain;

        // Process input in blocks
        let mut processed = 0;
        while processed < audio.len() {
            // Fill input buffer
            let to_copy = (fft_size - state.input_pos).min(audio.len() - processed);
            for i in 0..to_copy {
                state.input_buffer[state.input_pos + i] = audio[processed + i] * smooth_gain;
            }
            state.input_pos += to_copy;
            processed += to_copy;

            // Process when buffer is full
            if state.input_pos >= fft_size {
                self.convolve_block(state, &hrtf);
                state.input_pos = 0;
            }
        }

        // Add overlap to output
        let out_len = output_left.len().min(output_right.len());
        for i in 0..out_len.min(state.overlap_left.len()) {
            output_left[i] += state.overlap_left[i];
            output_right[i] += state.overlap_right[i];
        }
    }

    /// Convolve a block with HRTF
    fn convolve_block(&self, state: &mut SourceConvState, hrtf: &Hrtf) {
        let fft_size = self.config.fft_size;

        // FFT input
        let mut input_freq: Vec<Complex32> = state.input_buffer
            .iter()
            .map(|&x| Complex32::new(x, 0.0))
            .collect();
        self.fft_forward.process(&mut input_freq);

        // Multiply with HRTF in frequency domain
        let mut left_freq = vec![Complex32::new(0.0, 0.0); fft_size];
        let mut right_freq = vec![Complex32::new(0.0, 0.0); fft_size];

        for i in 0..fft_size {
            left_freq[i] = input_freq[i] * hrtf.left_freq[i];
            right_freq[i] = input_freq[i] * hrtf.right_freq[i];
        }

        // IFFT
        self.fft_inverse.process(&mut left_freq);
        self.fft_inverse.process(&mut right_freq);

        // Normalize and overlap-add
        let norm = 1.0 / fft_size as f32;
        for i in 0..fft_size {
            state.overlap_left[i] += left_freq[i].re * norm;
            state.overlap_right[i] += right_freq[i].re * norm;
        }
    }

    /// Render Ambisonic input to binaural
    pub fn render_ambisonic(
        &mut self,
        ambisonic: &[Vec<f32>],
        output_left: &mut [f32],
        output_right: &mut [f32],
    ) -> SpatialResult<()> {
        if ambisonic.len() < 4 {
            return Err(SpatialError::InvalidChannelCount {
                expected: 4,
                got: ambisonic.len(),
            });
        }

        let samples = ambisonic[0].len();
        output_left[..samples].fill(0.0);
        output_right[..samples].fill(0.0);

        // Virtual speaker decoding
        // Create virtual speakers on a sphere and decode ambisonics to them
        let virtual_speakers = [
            Position3D::from_spherical(-30.0, 0.0, 1.0),
            Position3D::from_spherical(30.0, 0.0, 1.0),
            Position3D::from_spherical(-110.0, 0.0, 1.0),
            Position3D::from_spherical(110.0, 0.0, 1.0),
            Position3D::from_spherical(0.0, 45.0, 1.0),
            Position3D::from_spherical(180.0, 0.0, 1.0),
        ];

        // Simple first-order decoding to virtual speakers
        for (spk_idx, spk_pos) in virtual_speakers.iter().enumerate() {
            let spherical = spk_pos.to_spherical();
            let az = spherical.azimuth.to_radians();
            let el = spherical.elevation.to_radians();

            // Decode coefficients (first order)
            let w_coeff = 0.707; // W
            let y_coeff = az.sin() * el.cos();
            let z_coeff = el.sin();
            let x_coeff = az.cos() * el.cos();

            // Create virtual speaker signal
            let mut speaker_signal = vec![0.0f32; samples];
            for i in 0..samples {
                speaker_signal[i] = ambisonic[0][i] * w_coeff
                    + ambisonic[1][i] * y_coeff
                    + ambisonic[2][i] * z_coeff
                    + ambisonic[3][i] * x_coeff;
            }

            // Get HRTF for this speaker position
            if let Some(hrir) = self.hrtf_db.get_hrir(spherical.azimuth, spherical.elevation) {
                // Simple convolution (time-domain for clarity)
                self.convolve_hrir(&speaker_signal, &hrir, output_left, output_right);
            }
        }

        // Apply crossfeed if enabled
        if let Some(ref mut cf) = self.crossfeed {
            cf.process(output_left, output_right);
        }

        Ok(())
    }

    /// Simple time-domain convolution with HRIR
    fn convolve_hrir(
        &self,
        input: &[f32],
        hrir: &HrirPair,
        output_left: &mut [f32],
        output_right: &mut [f32],
    ) {
        let filter_len = hrir.left.len().min(hrir.right.len());
        let input_len = input.len();
        let output_len = output_left.len().min(output_right.len());

        for i in 0..input_len {
            for j in 0..filter_len {
                let out_idx = i + j;
                if out_idx < output_len {
                    output_left[out_idx] += input[i] * hrir.left[j];
                    output_right[out_idx] += input[i] * hrir.right[j];
                }
            }
        }
    }
}

impl SpatialRenderer for BinauralRenderer {
    fn render(
        &mut self,
        objects: &[AudioObject],
        output: &mut [f32],
        output_channels: usize,
    ) -> SpatialResult<()> {
        if output_channels != 2 {
            return Err(SpatialError::InvalidChannelCount {
                expected: 2,
                got: output_channels,
            });
        }

        let samples = output.len() / 2;

        // Clear output
        output.fill(0.0);

        // Process each object
        for (obj_idx, obj) in objects.iter().enumerate().take(self.config.max_sources) {
            if obj.audio.is_empty() {
                continue;
            }

            // Create temporary output buffers
            let mut left = vec![0.0f32; samples];
            let mut right = vec![0.0f32; samples];

            // Get necessary values before mutable borrow
            let fft_size = self.config.fft_size;
            let head_tracking = self.config.head_tracking;
            let listener_pos = self.listener_pos;
            let listener_orient = self.listener_orient;

            // Transform position to listener-relative
            let relative_pos = if head_tracking {
                let world_rel = Position3D::new(
                    obj.position.x - listener_pos.x,
                    obj.position.y - listener_pos.y,
                    obj.position.z - listener_pos.z,
                );
                listener_orient.world_to_listener(&world_rel)
            } else {
                obj.position
            };

            let spherical = relative_pos.to_spherical();

            // Get HRTF for this direction
            let hrir = match self.hrtf_db.get_hrir(spherical.azimuth, spherical.elevation) {
                Some(h) => h,
                None => continue,
            };

            let hrtf = Hrtf::from_hrir(&hrir, spherical, fft_size);

            // Distance attenuation
            let distance = relative_pos.magnitude();
            let distance_gain = if distance > 0.1 {
                (1.0 / distance).min(1.0)
            } else {
                1.0
            };

            let total_gain = obj.gain * distance_gain;

            // Update state
            let state = &mut self.source_states[obj_idx];
            state.source_id = obj.id;

            // Smooth gain changes
            let smooth_gain = state.prev_gain * 0.9 + total_gain * 0.1;
            state.prev_gain = smooth_gain;

            // Simple processing - just apply gain and HRTF ITD/ILD
            let audio_slice = &obj.audio[..samples.min(obj.audio.len())];

            // Apply gain to output (simplified - full would use convolution)
            for (i, &s) in audio_slice.iter().enumerate() {
                left[i] = s * smooth_gain * hrir.left.get(0).copied().unwrap_or(1.0);
                right[i] = s * smooth_gain * hrir.right.get(0).copied().unwrap_or(1.0);
            }

            // Interleave to output
            for i in 0..samples {
                output[i * 2] += left[i];
                output[i * 2 + 1] += right[i];
            }
        }

        // Apply crossfeed
        if let Some(ref mut cf) = self.crossfeed {
            let mut left: Vec<f32> = output.iter().step_by(2).copied().collect();
            let mut right: Vec<f32> = output.iter().skip(1).step_by(2).copied().collect();

            cf.process(&mut left, &mut right);

            for (i, (&l, &r)) in left.iter().zip(right.iter()).enumerate() {
                output[i * 2] = l;
                output[i * 2 + 1] = r;
            }
        }

        Ok(())
    }

    fn output_layout(&self) -> &SpeakerLayout {
        // Binaural is always stereo
        static STEREO: std::sync::OnceLock<SpeakerLayout> = std::sync::OnceLock::new();
        STEREO.get_or_init(SpeakerLayout::stereo)
    }

    fn set_listener_position(&mut self, position: Position3D, orientation: Orientation) {
        self.listener_pos = position;
        self.listener_orient = orientation;
    }

    fn latency_samples(&self) -> usize {
        self.config.fft_size
    }

    fn reset(&mut self) {
        for state in &mut self.source_states {
            state.reset();
        }
        self.overlap_left.fill(0.0);
        self.overlap_right.fill(0.0);
        if let Some(ref mut cf) = self.crossfeed {
            cf.reset();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_binaural_renderer_creation() {
        let config = BinauralConfig::default();
        let renderer = BinauralRenderer::new(config, 48000);

        assert_eq!(renderer.latency_samples(), 1024);
    }

    #[test]
    fn test_render_objects() {
        let config = BinauralConfig::default();
        let mut renderer = BinauralRenderer::new(config, 48000);

        let objects = vec![
            AudioObject {
                id: 1,
                name: "Test".into(),
                position: Position3D::from_spherical(45.0, 0.0, 2.0),
                size: 0.0,
                gain: 1.0,
                audio: vec![0.5; 512],
                sample_rate: 48000,
                automation: None,
            },
        ];

        let mut output = vec![0.0f32; 1024]; // 512 samples stereo
        let result = renderer.render(&objects, &mut output, 2);

        assert!(result.is_ok());

        // Output should have some signal
        let sum: f32 = output.iter().map(|x| x.abs()).sum();
        assert!(sum > 0.0);
    }
}
