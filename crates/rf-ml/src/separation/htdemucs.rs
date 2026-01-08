//! HTDemucs v4 - Hybrid Transformer Demucs
//!
//! State-of-the-art music source separation using hybrid time-frequency
//! architecture with transformers. Achieves SDR > 9.0 dB on MUSDB18.
//!
//! ## Architecture
//!
//! HTDemucs combines:
//! - Time-domain U-Net encoder/decoder
//! - Frequency-domain spectral processing
//! - Cross-domain transformer attention
//! - Multi-head self-attention for long-range dependencies
//!
//! ## Model Variants
//!
//! - htdemucs: 4-stem (drums, bass, other, vocals)
//! - htdemucs_6s: 6-stem (+ piano, guitar)
//! - htdemucs_ft: Fine-tuned for higher quality

use std::path::Path;
use std::sync::Arc;

use ndarray::{Array2, Array3, Axis};
use num_complex::Complex32;
use realfft::{ComplexToReal, RealFftPlanner, RealToComplex};

use super::config::SeparationConfig;
use super::stems::{StemCollection, StemOutput, StemType};
use super::SourceSeparator;
use crate::error::{MlError, MlResult};
use crate::inference::{InferenceConfig, InferenceEngine};

/// HTDemucs model configuration
#[derive(Debug, Clone)]
pub struct HTDemucsConfig {
    /// Number of output stems
    pub num_stems: usize,

    /// Audio channels (1=mono, 2=stereo)
    pub audio_channels: usize,

    /// Model sample rate (always 44100 for Demucs)
    pub sample_rate: u32,

    /// STFT window size
    pub n_fft: usize,

    /// STFT hop length
    pub hop_length: usize,

    /// Segment length in samples
    pub segment_samples: usize,

    /// Overlap between segments (0.0 - 0.5)
    pub overlap: f32,

    /// Number of random shifts for test-time augmentation
    pub shifts: usize,

    /// Use Wiener filtering for post-processing
    pub wiener_filter: bool,

    /// Wiener filter iterations
    pub wiener_iterations: usize,
}

impl Default for HTDemucsConfig {
    fn default() -> Self {
        Self {
            num_stems: 4,
            audio_channels: 2,
            sample_rate: 44100,
            n_fft: 4096,
            hop_length: 1024,
            segment_samples: 44100 * 10, // 10 seconds
            overlap: 0.25,
            shifts: 1,
            wiener_filter: false,
            wiener_iterations: 1,
        }
    }
}

impl From<&SeparationConfig> for HTDemucsConfig {
    fn from(config: &SeparationConfig) -> Self {
        Self {
            num_stems: if config.use_6_stems { 6 } else { 4 },
            audio_channels: 2,
            sample_rate: 44100,
            n_fft: 4096,
            hop_length: 1024,
            segment_samples: (config.segment_length * 44100.0) as usize,
            overlap: config.overlap,
            shifts: config.shifts,
            wiener_filter: config.wiener_filter,
            wiener_iterations: config.wiener_iterations,
        }
    }
}

/// HTDemucs v4 separator
pub struct HTDemucs {
    /// Main model for inference
    model: InferenceEngine,

    /// Model configuration
    config: HTDemucsConfig,

    /// Separation configuration
    sep_config: SeparationConfig,

    /// FFT planner for STFT
    fft_forward: Arc<dyn RealToComplex<f32>>,

    /// IFFT planner for ISTFT
    fft_inverse: Arc<dyn ComplexToReal<f32>>,

    /// Window function (Hann)
    window: Vec<f32>,

    /// Stem names for this model
    stem_names: Vec<StemType>,

    /// Model name/version
    model_name: String,
}

impl HTDemucs {
    /// Load HTDemucs model from ONNX file
    pub fn new<P: AsRef<Path>>(model_path: P, config: SeparationConfig) -> MlResult<Self> {
        let model_path = model_path.as_ref();

        // Determine model variant from filename
        let model_name = model_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("htdemucs")
            .to_string();

        let htdemucs_config = HTDemucsConfig::from(&config);

        // Create inference engine
        let inference_config = InferenceConfig {
            use_gpu: config.use_gpu,
            batch_size: config.batch_size,
            ..Default::default()
        };

        let model = InferenceEngine::new(model_path, inference_config)?;

        // Create FFT planners
        let mut planner = RealFftPlanner::new();
        let fft_forward = planner.plan_fft_forward(htdemucs_config.n_fft);
        let fft_inverse = planner.plan_fft_inverse(htdemucs_config.n_fft);

        // Create Hann window
        let window = Self::create_hann_window(htdemucs_config.n_fft);

        // Determine stems based on model variant
        let stem_names = if config.use_6_stems {
            vec![
                StemType::Drums,
                StemType::Bass,
                StemType::Other,
                StemType::Vocals,
                StemType::Piano,
                StemType::Guitar,
            ]
        } else {
            vec![
                StemType::Drums,
                StemType::Bass,
                StemType::Other,
                StemType::Vocals,
            ]
        };

        Ok(Self {
            model,
            config: htdemucs_config,
            sep_config: config,
            fft_forward,
            fft_inverse,
            window,
            stem_names,
            model_name,
        })
    }

    /// Create Hann window
    fn create_hann_window(size: usize) -> Vec<f32> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / size as f32).cos()))
            .collect()
    }

    /// Compute STFT of audio
    fn stft(&self, audio: &[f32]) -> MlResult<Array3<Complex32>> {
        let n_fft = self.config.n_fft;
        let hop = self.config.hop_length;
        let n_frames = (audio.len() - n_fft) / hop + 1;
        let n_bins = n_fft / 2 + 1;

        let mut spectrum = Array3::<Complex32>::zeros((1, n_bins, n_frames));
        let mut input_buffer = vec![0.0f32; n_fft];
        let mut output_buffer = vec![Complex32::new(0.0, 0.0); n_bins];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft_forward.get_scratch_len()];

        for (frame_idx, start) in (0..audio.len() - n_fft + 1).step_by(hop).enumerate() {
            if frame_idx >= n_frames {
                break;
            }

            // Apply window
            for (i, &sample) in audio[start..start + n_fft].iter().enumerate() {
                input_buffer[i] = sample * self.window[i];
            }

            // FFT
            self.fft_forward
                .process_with_scratch(&mut input_buffer, &mut output_buffer, &mut scratch)
                .map_err(|e| MlError::ProcessingFailed(format!("FFT failed: {}", e)))?;

            // Store in spectrum array
            for (bin, &val) in output_buffer.iter().enumerate() {
                spectrum[[0, bin, frame_idx]] = val;
            }
        }

        Ok(spectrum)
    }

    /// Compute ISTFT to reconstruct audio
    fn istft(&self, spectrum: &Array3<Complex32>, length: usize) -> MlResult<Vec<f32>> {
        let n_fft = self.config.n_fft;
        let hop = self.config.hop_length;
        let n_bins = n_fft / 2 + 1;
        let n_frames = spectrum.shape()[2];

        let mut output = vec![0.0f32; length];
        let mut window_sum = vec![0.0f32; length];

        let mut input_buffer = vec![Complex32::new(0.0, 0.0); n_bins];
        let mut output_buffer = vec![0.0f32; n_fft];
        let mut scratch = vec![Complex32::new(0.0, 0.0); self.fft_inverse.get_scratch_len()];

        for frame_idx in 0..n_frames {
            let start = frame_idx * hop;
            if start + n_fft > length {
                break;
            }

            // Copy spectrum frame
            for bin in 0..n_bins {
                input_buffer[bin] = spectrum[[0, bin, frame_idx]];
            }

            // IFFT
            self.fft_inverse
                .process_with_scratch(&mut input_buffer, &mut output_buffer, &mut scratch)
                .map_err(|e| MlError::ProcessingFailed(format!("IFFT failed: {}", e)))?;

            // Normalize and apply window
            let norm = 1.0 / n_fft as f32;
            for (i, &sample) in output_buffer.iter().enumerate() {
                let pos = start + i;
                if pos < length {
                    output[pos] += sample * norm * self.window[i];
                    window_sum[pos] += self.window[i] * self.window[i];
                }
            }
        }

        // Normalize by window sum (overlap-add normalization)
        for (i, sum) in window_sum.iter().enumerate() {
            if *sum > 1e-8 {
                output[i] /= sum;
            }
        }

        Ok(output)
    }

    /// Apply random shift augmentation
    fn apply_shift(&self, audio: &Array2<f32>, shift: i32) -> Array2<f32> {
        if shift == 0 {
            return audio.clone();
        }

        let (channels, samples) = (audio.shape()[0], audio.shape()[1]);
        let mut shifted = Array2::<f32>::zeros((channels, samples));

        for ch in 0..channels {
            for i in 0..samples {
                let src_idx = ((i as i32 - shift).rem_euclid(samples as i32)) as usize;
                shifted[[ch, i]] = audio[[ch, src_idx]];
            }
        }

        shifted
    }

    /// Undo random shift
    fn undo_shift(&self, audio: &Array2<f32>, shift: i32) -> Array2<f32> {
        self.apply_shift(audio, -shift)
    }

    /// Process a single segment through the model
    fn process_segment(&self, segment: &Array2<f32>) -> MlResult<Array3<f32>> {
        let (_channels, _samples) = (segment.shape()[0], segment.shape()[1]);

        // Prepare input tensor: [batch, channels, samples]
        let input = segment.clone().insert_axis(Axis(0));

        // Run inference
        let output = self.model.run_array3(&input)?;

        // Output shape: [batch, stems, channels, samples]
        // We need to reshape to [stems, channels, samples]
        let stems = output.shape()[1];
        let out_channels = output.shape()[2];
        let out_samples = output.shape()[3];

        let mut result = Array3::<f32>::zeros((stems, out_channels, out_samples));
        for s in 0..stems {
            for c in 0..out_channels {
                for i in 0..out_samples {
                    result[[s, c, i]] = output[[0, s, c, i]];
                }
            }
        }

        Ok(result)
    }

    /// Apply Wiener filtering for post-processing
    fn apply_wiener_filter(
        &self,
        mix_stft: &Array3<Complex32>,
        stems_stft: &[Array3<Complex32>],
        iterations: usize,
    ) -> MlResult<Vec<Array3<Complex32>>> {
        let _n_stems = stems_stft.len();
        let shape = mix_stft.shape();

        let mut filtered = stems_stft.to_vec();

        for _ in 0..iterations {
            // Compute power spectrograms
            let powers: Vec<Array3<f32>> =
                filtered.iter().map(|s| s.map(|c| c.norm_sqr())).collect();

            // Compute total power
            let total_power: Array3<f32> = powers.iter().fold(
                Array3::<f32>::zeros((shape[0], shape[1], shape[2])),
                |acc, p| acc + p,
            );

            // Apply Wiener filter
            for (stem_idx, power) in powers.iter().enumerate() {
                let gain = power / (&total_power + 1e-10);

                for i in 0..shape[0] {
                    for j in 0..shape[1] {
                        for k in 0..shape[2] {
                            filtered[stem_idx][[i, j, k]] = mix_stft[[i, j, k]] * gain[[i, j, k]];
                        }
                    }
                }
            }
        }

        Ok(filtered)
    }

    /// Separate audio into stems
    fn separate_internal(&self, audio: &Array2<f32>) -> MlResult<Array3<f32>> {
        let (channels, total_samples) = (audio.shape()[0], audio.shape()[1]);
        let segment_len = self.config.segment_samples;
        let overlap_samples = (segment_len as f32 * self.config.overlap) as usize;
        let hop = segment_len - overlap_samples;

        let num_stems = self.stem_names.len();
        let mut output = Array3::<f32>::zeros((num_stems, channels, total_samples));
        let mut weight = Array2::<f32>::zeros((channels, total_samples));

        // Create fade window for overlap
        let fade_len = overlap_samples;
        let fade_in: Vec<f32> = (0..fade_len)
            .map(|i| (i as f32 / fade_len as f32).powi(2))
            .collect();
        let fade_out: Vec<f32> = fade_in.iter().rev().copied().collect();

        // Process with random shifts for test-time augmentation
        let shifts: Vec<i32> = if self.config.shifts > 0 {
            use std::collections::hash_map::DefaultHasher;
            use std::hash::{Hash, Hasher};

            let mut hasher = DefaultHasher::new();
            total_samples.hash(&mut hasher);
            let seed = hasher.finish();

            (0..self.config.shifts)
                .map(|i| {
                    let shift_seed = seed.wrapping_add(i as u64);
                    (shift_seed % (segment_len as u64 / 2)) as i32 - (segment_len as i32 / 4)
                })
                .collect()
        } else {
            vec![0]
        };

        for shift in &shifts {
            let shifted_audio = self.apply_shift(audio, *shift);

            // Process segments
            let mut start = 0;
            while start < total_samples {
                let end = (start + segment_len).min(total_samples);
                let actual_len = end - start;

                // Extract and pad segment
                let mut segment = Array2::<f32>::zeros((channels, segment_len));
                for ch in 0..channels {
                    for i in 0..actual_len {
                        segment[[ch, i]] = shifted_audio[[ch, start + i]];
                    }
                }

                // Process segment
                let stems_out = self.process_segment(&segment)?;

                // Apply fades and accumulate
                for s in 0..num_stems {
                    for ch in 0..channels {
                        for i in 0..actual_len {
                            let pos = start + i;
                            if pos >= total_samples {
                                break;
                            }

                            // Apply fade
                            let mut w = 1.0;
                            if start > 0 && i < fade_len {
                                w *= fade_in[i];
                            }
                            if pos + hop < total_samples && i >= actual_len - fade_len {
                                let fade_idx = i - (actual_len - fade_len);
                                w *= fade_out[fade_idx.min(fade_len - 1)];
                            }

                            // Undo shift before accumulating
                            let orig_pos =
                                ((pos as i32 + shift).rem_euclid(total_samples as i32)) as usize;

                            output[[s, ch, orig_pos]] += stems_out[[s, ch, i]] * w;
                            if s == 0 {
                                weight[[ch, orig_pos]] += w;
                            }
                        }
                    }
                }

                start += hop;
            }
        }

        // Normalize by weights
        for s in 0..num_stems {
            for ch in 0..channels {
                for i in 0..total_samples {
                    if weight[[ch, i]] > 1e-8 {
                        output[[s, ch, i]] /= weight[[ch, i]];
                    }
                }
            }
        }

        Ok(output)
    }

    /// Compute SDR (Signal-to-Distortion Ratio) for quality estimation
    fn compute_sdr(reference: &[f32], estimate: &[f32]) -> f32 {
        let n = reference.len().min(estimate.len());

        let mut ref_power = 0.0f64;
        let mut error_power = 0.0f64;

        for i in 0..n {
            let r = reference[i] as f64;
            let e = estimate[i] as f64;
            ref_power += r * r;
            error_power += (r - e) * (r - e);
        }

        if error_power < 1e-10 {
            return f32::INFINITY;
        }

        10.0 * (ref_power / error_power).log10() as f32
    }
}

impl SourceSeparator for HTDemucs {
    fn separate(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<StemCollection> {
        // Validate input
        if audio.is_empty() {
            return Err(MlError::InvalidInputShape {
                expected: "non-empty audio".into(),
                got: "empty".into(),
            });
        }

        // Resample if needed (Demucs requires 44.1kHz)
        let (resampled, actual_samples) = if sample_rate != self.config.sample_rate {
            let ratio = self.config.sample_rate as f64 / sample_rate as f64;
            let new_len = (audio.len() as f64 * ratio) as usize;

            // Simple linear resampling (TODO: use proper resampler)
            let mut resampled = Vec::with_capacity(new_len);
            for i in 0..new_len {
                let src_pos = i as f64 / ratio;
                let src_idx = src_pos.floor() as usize;
                let frac = src_pos - src_idx as f64;

                let sample = if src_idx + 1 < audio.len() {
                    audio[src_idx] as f64 * (1.0 - frac) + audio[src_idx + 1] as f64 * frac
                } else if src_idx < audio.len() {
                    audio[src_idx] as f64
                } else {
                    0.0
                };
                resampled.push(sample as f32);
            }

            (resampled, new_len / channels)
        } else {
            (audio.to_vec(), audio.len() / channels)
        };

        let samples_per_channel = actual_samples;

        // Convert to Array2 [channels, samples]
        let mut input = Array2::<f32>::zeros((channels, samples_per_channel));
        for ch in 0..channels {
            for i in 0..samples_per_channel {
                input[[ch, i]] = resampled[i * channels + ch];
            }
        }

        // Pad to stereo if mono
        let input = if channels == 1 {
            let mut stereo = Array2::<f32>::zeros((2, samples_per_channel));
            for i in 0..samples_per_channel {
                stereo[[0, i]] = input[[0, i]];
                stereo[[1, i]] = input[[0, i]];
            }
            stereo
        } else {
            input
        };

        // Run separation
        let stems_array = self.separate_internal(&input)?;

        // Convert to StemCollection
        let mut collection = StemCollection::new(self.config.sample_rate, self.model_name.clone());

        for (idx, stem_type) in self.stem_names.iter().enumerate() {
            let stem_channels = stems_array.shape()[1];
            let stem_samples = stems_array.shape()[2];

            // Interleave channels
            let mut audio = Vec::with_capacity(stem_samples * stem_channels);
            for i in 0..stem_samples {
                for ch in 0..stem_channels {
                    audio.push(stems_array[[idx, ch, i]]);
                }
            }

            // Create stem output using proper constructor
            let mut output =
                StemOutput::new(*stem_type, audio, stem_channels, self.config.sample_rate);

            // Set confidence metric
            output.metrics.confidence = 0.9;

            collection.add(output);
        }

        Ok(collection)
    }

    fn available_stems(&self) -> &[StemType] {
        &self.stem_names
    }

    fn model_name(&self) -> &str {
        &self.model_name
    }

    fn supports_realtime(&self) -> bool {
        false // HTDemucs is not suitable for real-time
    }

    fn estimated_memory_mb(&self, duration_secs: f32) -> f32 {
        self.sep_config
            .estimated_memory_mb(duration_secs, self.config.sample_rate)
    }
}

/// Create HTDemucs with default 4-stem model
pub fn create_htdemucs_4stem<P: AsRef<Path>>(model_path: P) -> MlResult<HTDemucs> {
    HTDemucs::new(model_path, SeparationConfig::default())
}

/// Create HTDemucs with 6-stem model
pub fn create_htdemucs_6stem<P: AsRef<Path>>(model_path: P) -> MlResult<HTDemucs> {
    HTDemucs::new(model_path, SeparationConfig::default().with_6_stems())
}

/// Create HTDemucs with ultra quality settings
pub fn create_htdemucs_ultra<P: AsRef<Path>>(model_path: P) -> MlResult<HTDemucs> {
    HTDemucs::new(model_path, SeparationConfig::ultra())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hann_window() {
        let window = HTDemucs::create_hann_window(1024);
        assert_eq!(window.len(), 1024);
        assert!(window[0] < 0.01); // Start near zero
        assert!(window[512] > 0.99); // Peak in middle
        assert!(window[1023] < 0.01); // End near zero
    }

    #[test]
    fn test_config_from_separation_config() {
        let sep_config = SeparationConfig::ultra();
        let htdemucs_config = HTDemucsConfig::from(&sep_config);

        assert_eq!(htdemucs_config.num_stems, 6);
        assert_eq!(htdemucs_config.overlap, 0.5);
        assert!(htdemucs_config.wiener_filter);
    }

    #[test]
    fn test_sdr_computation() {
        let reference = vec![1.0, 0.0, -1.0, 0.0];
        let perfect = reference.clone();
        let sdr = HTDemucs::compute_sdr(&reference, &perfect);
        assert!(sdr > 100.0 || sdr.is_infinite());

        let noisy: Vec<f32> = reference.iter().map(|x| x + 0.1).collect();
        let sdr_noisy = HTDemucs::compute_sdr(&reference, &noisy);
        assert!(sdr_noisy > 0.0);
        assert!(sdr_noisy < 30.0);
    }
}
