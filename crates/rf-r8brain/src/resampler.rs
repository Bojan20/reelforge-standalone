//! R8brain Resampler — Multi-stage pipeline orchestrator
//!
//! Automatically constructs optimal resampling pipeline based on
//! source/destination sample rate ratio:
//!
//! 1. Half-band stages for power-of-2 rate changes (2x, 4x, 8x...)
//! 2. FFT block convolver for anti-aliasing
//! 3. Polynomial fractional interpolator for fine ratio adjustment
//!
//! Quality presets match r8brain:
//! - R8brain206: 206.91 dB (27-bit fixed point quality)
//! - R8brain180: 180.15 dB (24-bit / 32-bit float quality)
//! - R8brain136: 136.45 dB (16-bit quality)

use crate::frac_interpolator::FracInterpolator;
use crate::halfband::{HBUpsampler, HBDownsampler};
use crate::block_convolver::BlockConvolver;
use crate::kaiser;

/// Quality preset for the resampler
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum R8brainQuality {
    /// 206.91 dB — reference quality (27-bit)
    Quality206,
    /// 180.15 dB — high quality (24-bit / 32-bit float)
    Quality180,
    /// 136.45 dB — standard quality (16-bit)
    Quality136,
}

impl R8brainQuality {
    /// Stopband attenuation in dB
    pub fn attenuation(self) -> f64 {
        match self {
            Self::Quality206 => 206.91,
            Self::Quality180 => 180.15,
            Self::Quality136 => 136.45,
        }
    }

    /// Transition band width as fraction of sample rate
    pub fn transition_band(self) -> f64 {
        match self {
            Self::Quality206 => 0.01,  // 1% — very narrow, very precise
            Self::Quality180 => 0.02,  // 2% — good balance (r8brain default)
            Self::Quality136 => 0.05,  // 5% — wider, less CPU
        }
    }
}

impl Default for R8brainQuality {
    fn default() -> Self {
        Self::Quality180
    }
}

/// R8brain resampler — multi-stage pipeline.
///
/// Processes audio in blocks. Push input → get output (input-driven mode).
///
/// # Example
/// ```
/// use rf_r8brain::resampler::{R8brainResampler, R8brainQuality};
///
/// let mut resampler = R8brainResampler::new(44100.0, 48000.0, 256, R8brainQuality::Quality180);
/// let input = vec![0.0f64; 256];
/// let mut output = vec![0.0f64; 512]; // Generous output buffer
/// let written = resampler.process(&input, &mut output);
/// ```
impl std::fmt::Debug for R8brainResampler {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("R8brainResampler")
            .field("source_rate", &self.source_rate)
            .field("dest_rate", &self.dest_rate)
            .field("ratio", &self.ratio)
            .field("quality", &self.quality)
            .finish()
    }
}

pub struct R8brainResampler {
    /// Source sample rate
    source_rate: f64,
    /// Destination sample rate
    dest_rate: f64,
    /// Effective ratio (dest / source)
    ratio: f64,
    /// Quality settings
    quality: R8brainQuality,
    /// Fractional interpolator (core — always present)
    frac_interp: FracInterpolator,
    /// Half-band upsampler stages (for upsampling path)
    hb_upsamplers: Vec<HBUpsampler>,
    /// Half-band downsampler stages (for downsampling path)
    hb_downsamplers: Vec<HBDownsampler>,
    /// Anti-aliasing block convolver (optional — for non-trivial ratios)
    convolver: Option<BlockConvolver>,
    /// Use minimum-phase filters (lower latency)
    use_min_phase: bool,
    /// Internal accumulator for fractional position tracking
    frac_pos: f64,
    /// Intermediate buffers for multi-stage processing
    stage_buf_a: Vec<f64>,
    stage_buf_b: Vec<f64>,
}

impl R8brainResampler {
    /// Create a new resampler for the given sample rate conversion.
    ///
    /// `source_rate`: input sample rate (e.g., 44100.0)
    /// `dest_rate`: output sample rate (e.g., 48000.0)
    /// `max_block`: maximum input block size
    /// `quality`: quality preset
    pub fn new(
        source_rate: f64,
        dest_rate: f64,
        max_block: usize,
        quality: R8brainQuality,
    ) -> Self {
        let ratio = dest_rate / source_rate;
        let atten = quality.attenuation();
        let transition = quality.transition_band();

        // Determine pipeline stages
        let mut hb_upsamplers = Vec::new();
        let mut hb_downsamplers = Vec::new();
        let mut convolver = None;

        // Calculate how many 2x stages we need
        let mut working_ratio = ratio;
        let mut steepness = 0usize;

        if ratio > 1.0 {
            // Upsampling: add half-band 2x stages for each power-of-2
            while working_ratio >= 2.0 && steepness < 6 {
                hb_upsamplers.push(HBUpsampler::new(steepness));
                working_ratio /= 2.0;
                steepness += 1;
            }
        } else if ratio < 1.0 {
            // Downsampling: add half-band 2x stages
            let inv_ratio = 1.0 / ratio;
            working_ratio = inv_ratio;
            while working_ratio >= 2.0 && steepness < 6 {
                hb_downsamplers.push(HBDownsampler::new(steepness));
                working_ratio /= 2.0;
                steepness += 1;
            }
            working_ratio = 1.0 / working_ratio; // Back to < 1.0
        }

        // If remaining ratio is not 1.0, need anti-aliasing + fractional interpolation
        if (working_ratio - 1.0).abs() > 1e-10 {
            // Anti-aliasing filter for the fractional part
            let cutoff = if working_ratio < 1.0 {
                working_ratio * (1.0 - transition)
            } else {
                (1.0 - transition) / working_ratio
            };
            let cutoff = cutoff.clamp(0.01, 0.99);

            let filter_len = kaiser::filter_length(atten, transition);
            let filter_len = filter_len.min(512); // Cap for real-time
            let kernel = kaiser::generate_sinc_filter(cutoff, filter_len, atten);

            convolver = Some(BlockConvolver::new(&kernel, max_block));
        }

        // Fractional interpolator for final fine adjustment
        let frac_filter_len = if atten > 180.0 { 24 } else if atten > 130.0 { 16 } else { 10 };
        let frac_cutoff = (1.0 - transition).clamp(0.5, 0.99);
        let frac_interp = FracInterpolator::new(frac_filter_len, frac_cutoff, atten);

        // Intermediate buffers: must accommodate all upsampling stages.
        // Each HB stage doubles the sample count. Max 6 stages = 64x.
        let up_factor = 1usize << hb_upsamplers.len(); // 2^stages
        let buf_size = (max_block * up_factor * 2).max(max_block * 4); // ×2 safety margin
        let stage_buf_a = vec![0.0f64; buf_size];
        let stage_buf_b = vec![0.0f64; buf_size];

        Self {
            source_rate,
            dest_rate,
            ratio,
            quality,
            frac_interp,
            hb_upsamplers,
            hb_downsamplers,
            convolver,
            use_min_phase: false,
            frac_pos: 0.0,
            stage_buf_a,
            stage_buf_b,
        }
    }

    /// Enable minimum-phase mode (lower latency, non-linear phase).
    pub fn set_min_phase(&mut self, enabled: bool) {
        self.use_min_phase = enabled;
    }

    /// Process a block of input samples, producing resampled output.
    ///
    /// `input`: input audio samples at source sample rate
    /// `output`: output buffer (must be large enough for resampled data)
    ///
    /// Returns: number of output samples written.
    ///
    /// Zero-allocation in steady state (all buffers pre-allocated).
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) -> usize {
        if input.is_empty() || output.is_empty() {
            return 0;
        }

        let mut current = input;
        let mut current_len = input.len();

        // Stage 1: Half-band upsampling (if any)
        for up in &mut self.hb_upsamplers {
            let out_len = current_len * 2;
            if out_len > self.stage_buf_a.len() {
                self.stage_buf_a.resize(out_len, 0.0);
            }
            up.process(current, &mut self.stage_buf_a[..out_len]);
            // Swap buffers
            std::mem::swap(&mut self.stage_buf_a, &mut self.stage_buf_b);
            current_len = out_len;
            current = &self.stage_buf_b[..current_len];
        }

        // Stage 2: Anti-aliasing convolution (if needed)
        if let Some(ref mut conv) = self.convolver {
            // Convolver may produce up to current_len output samples
            let needed = current_len.max(256);
            if needed > self.stage_buf_a.len() {
                self.stage_buf_a.resize(needed, 0.0);
            }
            let written = conv.process(current, &mut self.stage_buf_a[..needed]);
            current_len = written;
            std::mem::swap(&mut self.stage_buf_a, &mut self.stage_buf_b);
            current = &self.stage_buf_b[..current_len];
        }

        // Stage 3: Fractional interpolation
        let frac_ratio = self.ratio
            / (1 << self.hb_upsamplers.len()) as f64
            * (1 << self.hb_downsamplers.len()) as f64;

        // Guard: don't read beyond buffer (filter needs taps beyond position)
        let safe_limit = (current_len as f64 - self.frac_interp.filter_len() as f64).max(0.0);

        let mut out_idx = 0;
        while self.frac_pos < safe_limit && out_idx < output.len() {
            output[out_idx] = self.frac_interp.interpolate(current, self.frac_pos, current_len);
            out_idx += 1;
            self.frac_pos += 1.0 / frac_ratio;
        }
        // Keep fractional remainder for next block.
        // frac_pos now points past processed samples — subtract to get
        // offset within next block's input.
        self.frac_pos -= current_len as f64;
        // Clamp: negative remainder means we consumed all input and need
        // more before producing next output. Keep the negative offset
        // so next block starts at the right fractional position.
        // Only clamp to 0 if very negative (numerical error).
        if self.frac_pos < -1.0 {
            self.frac_pos = 0.0;
        }

        let mut result_len = out_idx;

        // Stage 4: Half-band downsampling (if any)
        for down in &mut self.hb_downsamplers {
            if result_len % 2 != 0 {
                // Pad to even length
                if result_len < output.len() {
                    output[result_len] = 0.0;
                    result_len += 1;
                }
            }
            let down_len = result_len / 2;
            if down_len > self.stage_buf_a.len() {
                self.stage_buf_a.resize(down_len, 0.0);
            }
            down.process(&output[..result_len], &mut self.stage_buf_a[..down_len]);
            output[..down_len].copy_from_slice(&self.stage_buf_a[..down_len]);
            // Scale by 0.5 (downsampler has 2.0 gain)
            for s in &mut output[..down_len] {
                *s *= 0.5;
            }
            result_len = down_len;
        }

        result_len
    }

    /// Reset internal state (call when seeking or starting new stream)
    pub fn reset(&mut self) {
        self.frac_pos = 0.0;
        for up in &mut self.hb_upsamplers {
            up.reset();
        }
        for down in &mut self.hb_downsamplers {
            down.reset();
        }
        if let Some(ref mut conv) = self.convolver {
            conv.reset();
        }
    }

    /// Total latency in input samples
    pub fn latency(&self) -> usize {
        let mut lat = self.frac_interp.latency();
        for up in &self.hb_upsamplers {
            lat += up.latency();
        }
        for down in &self.hb_downsamplers {
            lat += down.latency();
        }
        if let Some(ref conv) = self.convolver {
            lat += conv.latency();
        }
        lat
    }

    /// Source sample rate
    pub fn source_rate(&self) -> f64 {
        self.source_rate
    }

    /// Destination sample rate
    pub fn dest_rate(&self) -> f64 {
        self.dest_rate
    }

    /// Effective ratio (dest / source)
    pub fn ratio(&self) -> f64 {
        self.ratio
    }

    /// Quality preset
    pub fn quality(&self) -> R8brainQuality {
        self.quality
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identity_ratio() {
        // 48000 → 48000 should pass through
        let mut r = R8brainResampler::new(48000.0, 48000.0, 256, R8brainQuality::Quality180);
        let input = vec![1.0f64; 256];
        let mut output = vec![0.0f64; 512];
        let written = r.process(&input, &mut output);
        assert!(written > 0);
    }

    #[test]
    fn test_upsample_ratio() {
        // 44100 → 48000 (common case)
        let mut r = R8brainResampler::new(44100.0, 48000.0, 256, R8brainQuality::Quality180);
        let input = vec![1.0f64; 256];
        let mut output = vec![0.0f64; 512];
        let written = r.process(&input, &mut output);

        // Should produce ~278 samples (256 * 48000/44100)
        assert!(written > 250, "Too few output samples: {written}");
        assert!(written < 300, "Too many output samples: {written}");
    }

    #[test]
    fn test_downsample_ratio() {
        // 96000 → 48000 (2x downsample)
        let mut r = R8brainResampler::new(96000.0, 48000.0, 256, R8brainQuality::Quality180);
        let input = vec![1.0f64; 256];
        let mut output = vec![0.0f64; 256];
        let written = r.process(&input, &mut output);

        // Should produce ~128 samples
        assert!(written > 100, "Too few: {written}");
        assert!(written < 160, "Too many: {written}");
    }

    #[test]
    fn test_dc_preservation() {
        // DC (all 1.0) should remain ~1.0 after resampling.
        // The anti-aliasing convolver has significant latency (kernel_len - 1
        // samples), so we need a long input and generous settling skip.
        let mut r = R8brainResampler::new(44100.0, 48000.0, 1024, R8brainQuality::Quality136);

        // Process multiple blocks to allow full settling through the
        // convolver + interpolator pipeline.
        let block = vec![1.0f64; 1024];
        let mut all_output = Vec::new();
        for _ in 0..4 {
            let mut output = vec![0.0f64; 2048];
            let written = r.process(&block, &mut output);
            all_output.extend_from_slice(&output[..written]);
        }

        // Skip first 500 output samples for convolver settling
        // (kernel can be ~180 taps → ~200 output samples of latency)
        assert!(all_output.len() > 600, "Not enough output: {}", all_output.len());
        let settled = &all_output[500..];
        for &s in settled {
            assert!((s - 1.0).abs() < 0.15, "DC not preserved: {s}");
        }
    }

    #[test]
    fn test_latency() {
        let r = R8brainResampler::new(44100.0, 48000.0, 256, R8brainQuality::Quality180);
        let lat = r.latency();
        assert!(lat > 0, "Should have non-zero latency");
        assert!(lat < 1000, "Latency too high: {lat}");
    }

    #[test]
    fn test_reset() {
        let mut r = R8brainResampler::new(44100.0, 48000.0, 256, R8brainQuality::Quality180);
        let input = vec![1.0f64; 256];
        let mut output = vec![0.0f64; 512];
        r.process(&input, &mut output);
        r.reset();
        // After reset, should be able to process again
        let written = r.process(&input, &mut output);
        assert!(written > 0);
    }

    #[test]
    fn test_empty_input() {
        let mut r = R8brainResampler::new(44100.0, 48000.0, 256, R8brainQuality::Quality180);
        let mut output = vec![0.0f64; 512];
        let written = r.process(&[], &mut output);
        assert_eq!(written, 0);
    }

    #[test]
    fn test_quality_presets() {
        assert!(R8brainQuality::Quality206.attenuation() > 200.0);
        assert!(R8brainQuality::Quality180.attenuation() > 170.0);
        assert!(R8brainQuality::Quality136.attenuation() > 130.0);
    }
}
