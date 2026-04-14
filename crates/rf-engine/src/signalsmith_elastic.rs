//! Signalsmith Stretch wrapper for per-clip offline elastic processing.
//!
//! Replaces ElasticPro (custom PhaseVocoder) with Signalsmith Stretch (MIT).
//! Quality matches or exceeds zplane Élastique Pro.

use rf_dsp::elastic_pro::{ElasticProConfig, StretchMode, StretchQuality};
use signalsmith_stretch::Stretch;

pub struct SignalsmithElastic {
    inner: Stretch,
    config: ElasticProConfig,
}

impl SignalsmithElastic {
    pub fn new(sample_rate: f64) -> Self {
        let inner = Stretch::preset_default(2, sample_rate as u32);
        Self {
            inner,
            config: ElasticProConfig::default(),
        }
    }

    pub fn config(&self) -> &ElasticProConfig {
        &self.config
    }

    pub fn set_config(&mut self, config: ElasticProConfig) {
        self.config = config;
        self.apply_config();
    }

    pub fn set_stretch_ratio(&mut self, ratio: f64) {
        self.config.stretch_ratio = ratio.clamp(0.1, 10.0);
    }

    pub fn set_pitch_shift(&mut self, semitones: f64) {
        self.config.pitch_shift = semitones.clamp(-24.0, 24.0);
        self.inner
            .set_transpose_factor_semitones(self.config.pitch_shift as f32, None);
    }

    pub fn set_quality(&mut self, quality: StretchQuality) {
        self.config.quality = quality;
    }

    pub fn set_mode(&mut self, mode: StretchMode) {
        self.config.mode = mode;
    }

    pub fn output_length(&self, input_length: usize) -> usize {
        (input_length as f64 * self.config.stretch_ratio) as usize
    }

    pub fn reset(&mut self) {
        self.inner.reset();
    }

    fn apply_config(&mut self) {
        self.inner
            .set_transpose_factor_semitones(self.config.pitch_shift as f32, None);
        if self.config.preserve_formants {
            self.inner.set_formant_factor(1.0, true);
        } else {
            self.inner.set_formant_factor(0.0, false);
        }
    }

    /// Offline mono processing — time stretch + pitch shift in one pass.
    pub fn process(&mut self, input: &[f64]) -> Vec<f64> {
        if input.is_empty() {
            return vec![];
        }

        let stretch_ratio = self.config.stretch_ratio;
        let total_in_frames = input.len();
        let total_out_frames = (total_in_frames as f64 * stretch_ratio).ceil() as usize;

        if total_out_frames == 0 {
            return vec![];
        }

        self.inner
            .set_transpose_factor_semitones(self.config.pitch_shift as f32, None);
        if self.config.preserve_formants {
            self.inner.set_formant_factor(1.0, true);
        }

        let mut output = vec![0.0f64; total_out_frames];

        let block_in = 4096usize;
        let mut in_pos = 0usize;
        let mut out_pos = 0usize;

        // Pre-feed silence to flush internal latency
        let latency = self.inner.input_latency() + self.inner.output_latency();
        if latency > 0 {
            let silence_in = vec![0.0f32; latency * 2]; // stereo interleaved
            let mut silence_out = vec![0.0f32; latency * 2];
            self.inner.process(&silence_in, &mut silence_out);
        }

        while in_pos < total_in_frames && out_pos < total_out_frames {
            let this_in = block_in.min(total_in_frames - in_pos);
            let this_out = ((this_in as f64 * stretch_ratio).ceil() as usize)
                .min(total_out_frames - out_pos)
                .max(1);

            // Convert mono f64 → stereo interleaved f32 (duplicate to both channels)
            let mut interleaved_in = vec![0.0f32; this_in * 2];
            for i in 0..this_in {
                let s = input[in_pos + i] as f32;
                interleaved_in[i * 2] = s;
                interleaved_in[i * 2 + 1] = s;
            }

            let mut interleaved_out = vec![0.0f32; this_out * 2];
            self.inner.process(&interleaved_in, &mut interleaved_out);

            // Extract left channel only (mono output)
            for i in 0..this_out {
                if out_pos + i < total_out_frames {
                    output[out_pos + i] = interleaved_out[i * 2] as f64;
                }
            }

            in_pos += this_in;
            out_pos += this_out;
        }

        // Flush tail
        let flush_frames = 4096;
        let silence_in = vec![0.0f32; flush_frames * 2];
        let mut flush_out = vec![0.0f32; flush_frames * 2];
        for _ in 0..4 {
            self.inner.process(&silence_in, &mut flush_out);
            for i in 0..flush_frames {
                if out_pos + i < total_out_frames {
                    output[out_pos + i] = flush_out[i * 2] as f64;
                }
            }
            out_pos += flush_frames;
            if out_pos >= total_out_frames {
                break;
            }
        }

        output
    }

    /// Offline stereo processing — both channels in one Signalsmith pass.
    pub fn process_stereo(&mut self, left: &[f64], right: &[f64]) -> (Vec<f64>, Vec<f64>) {
        if left.is_empty() || right.is_empty() {
            return (vec![], vec![]);
        }

        let stretch_ratio = self.config.stretch_ratio;
        let total_in_frames = left.len().min(right.len());
        let total_out_frames = (total_in_frames as f64 * stretch_ratio).ceil() as usize;

        if total_out_frames == 0 {
            return (vec![], vec![]);
        }

        self.inner
            .set_transpose_factor_semitones(self.config.pitch_shift as f32, None);
        if self.config.preserve_formants {
            self.inner.set_formant_factor(1.0, true);
        }

        let mut out_l = vec![0.0f64; total_out_frames];
        let mut out_r = vec![0.0f64; total_out_frames];

        let block_in = 4096usize;
        let mut in_pos = 0usize;
        let mut out_pos = 0usize;

        // Pre-feed silence to flush internal latency
        let latency = self.inner.input_latency() + self.inner.output_latency();
        if latency > 0 {
            let silence_in = vec![0.0f32; latency * 2];
            let mut silence_out = vec![0.0f32; latency * 2];
            self.inner.process(&silence_in, &mut silence_out);
        }

        while in_pos < total_in_frames && out_pos < total_out_frames {
            let this_in = block_in.min(total_in_frames - in_pos);
            let this_out = ((this_in as f64 * stretch_ratio).ceil() as usize)
                .min(total_out_frames - out_pos)
                .max(1);

            let mut interleaved_in = vec![0.0f32; this_in * 2];
            for i in 0..this_in {
                interleaved_in[i * 2] = left[in_pos + i] as f32;
                interleaved_in[i * 2 + 1] = right[in_pos + i] as f32;
            }

            let mut interleaved_out = vec![0.0f32; this_out * 2];
            self.inner.process(&interleaved_in, &mut interleaved_out);

            for i in 0..this_out {
                if out_pos + i < total_out_frames {
                    out_l[out_pos + i] = interleaved_out[i * 2] as f64;
                    out_r[out_pos + i] = interleaved_out[i * 2 + 1] as f64;
                }
            }

            in_pos += this_in;
            out_pos += this_out;
        }

        // Flush tail
        let flush_frames = 4096;
        let silence_in = vec![0.0f32; flush_frames * 2];
        let mut flush_out = vec![0.0f32; flush_frames * 2];
        for _ in 0..4 {
            self.inner.process(&silence_in, &mut flush_out);
            for i in 0..flush_frames {
                if out_pos + i < total_out_frames {
                    out_l[out_pos + i] = flush_out[i * 2] as f64;
                    out_r[out_pos + i] = flush_out[i * 2 + 1] as f64;
                }
            }
            out_pos += flush_frames;
            if out_pos >= total_out_frames {
                break;
            }
        }

        (out_l, out_r)
    }
}
