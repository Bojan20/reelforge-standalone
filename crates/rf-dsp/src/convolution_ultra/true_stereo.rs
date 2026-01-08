//! True Stereo Convolution
//!
//! 4-channel IR convolution for authentic stereo reverb:
//! - L→L (Left input to Left output)
//! - L→R (Left input to Right output)
//! - R→L (Right input to Left output)
//! - R→R (Right input to Right output)
//!
//! Beyond Altiverb, Spaces, LiquidSonics

use super::{ImpulseResponse, PartitionedConvolver};
use rf_core::Sample;

/// True stereo IR container
#[derive(Clone)]
pub struct TrueStereoIR {
    /// Left → Left impulse response
    pub ll: ImpulseResponse,
    /// Left → Right impulse response
    pub lr: ImpulseResponse,
    /// Right → Left impulse response
    pub rl: ImpulseResponse,
    /// Right → Right impulse response
    pub rr: ImpulseResponse,
    /// Sample rate
    pub sample_rate: f64,
}

impl TrueStereoIR {
    /// Create from 4 mono IRs
    pub fn new(
        ll: Vec<Sample>,
        lr: Vec<Sample>,
        rl: Vec<Sample>,
        rr: Vec<Sample>,
        sample_rate: f64,
    ) -> Self {
        Self {
            ll: ImpulseResponse::new(ll, sample_rate, 1),
            lr: ImpulseResponse::new(lr, sample_rate, 1),
            rl: ImpulseResponse::new(rl, sample_rate, 1),
            rr: ImpulseResponse::new(rr, sample_rate, 1),
            sample_rate,
        }
    }

    /// Create from stereo recording pair
    /// Assumes standard True Stereo measurement:
    /// - First stereo file: L speaker response
    /// - Second stereo file: R speaker response
    pub fn from_stereo_pair(
        left_response: &ImpulseResponse,
        right_response: &ImpulseResponse,
    ) -> Self {
        assert_eq!(left_response.channels, 2);
        assert_eq!(right_response.channels, 2);
        assert_eq!(left_response.sample_rate, right_response.sample_rate);

        Self {
            ll: ImpulseResponse::new(left_response.channel(0), left_response.sample_rate, 1),
            lr: ImpulseResponse::new(left_response.channel(1), left_response.sample_rate, 1),
            rl: ImpulseResponse::new(right_response.channel(0), right_response.sample_rate, 1),
            rr: ImpulseResponse::new(right_response.channel(1), right_response.sample_rate, 1),
            sample_rate: left_response.sample_rate,
        }
    }

    /// Create from single stereo IR (dual mono mode)
    pub fn from_stereo(ir: &ImpulseResponse) -> Self {
        assert_eq!(ir.channels, 2);

        let left = ir.channel(0);
        let right = ir.channel(1);

        Self {
            ll: ImpulseResponse::new(left.clone(), ir.sample_rate, 1),
            lr: ImpulseResponse::new(vec![0.0; left.len()], ir.sample_rate, 1), // No cross-feed
            rl: ImpulseResponse::new(vec![0.0; right.len()], ir.sample_rate, 1),
            rr: ImpulseResponse::new(right, ir.sample_rate, 1),
            sample_rate: ir.sample_rate,
        }
    }

    /// Max length across all IRs
    pub fn max_len(&self) -> usize {
        self.ll
            .len()
            .max(self.lr.len())
            .max(self.rl.len())
            .max(self.rr.len())
    }

    /// Duration in seconds
    pub fn duration(&self) -> f64 {
        self.max_len() as f64 / self.sample_rate
    }
}

/// True Stereo convolver
pub struct TrueStereoConvolver {
    /// L→L convolver
    ll: PartitionedConvolver,
    /// L→R convolver
    lr: PartitionedConvolver,
    /// R→L convolver
    rl: PartitionedConvolver,
    /// R→R convolver
    rr: PartitionedConvolver,
    /// Stereo width (0 = mono, 1 = full true stereo)
    width: f64,
    /// Cross-feed amount (0 = none, 1 = full)
    cross_feed: f64,
    /// Dry/wet mix
    mix: f64,
}

impl TrueStereoConvolver {
    /// Create new true stereo convolver
    pub fn new(ir: &TrueStereoIR, partition_size: usize) -> Self {
        Self {
            ll: PartitionedConvolver::new(&ir.ll, partition_size),
            lr: PartitionedConvolver::new(&ir.lr, partition_size),
            rl: PartitionedConvolver::new(&ir.rl, partition_size),
            rr: PartitionedConvolver::new(&ir.rr, partition_size),
            width: 1.0,
            cross_feed: 1.0,
            mix: 1.0,
        }
    }

    /// Set stereo width (0 = mono, 1 = full stereo)
    pub fn set_width(&mut self, width: f64) {
        self.width = width.clamp(0.0, 2.0);
    }

    /// Set cross-feed amount
    pub fn set_cross_feed(&mut self, amount: f64) {
        self.cross_feed = amount.clamp(0.0, 1.0);
    }

    /// Set dry/wet mix
    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Process stereo input
    pub fn process(
        &mut self,
        input_left: &[Sample],
        input_right: &[Sample],
    ) -> (Vec<Sample>, Vec<Sample>) {
        // Process all 4 convolutions
        let ll_out = self.ll.process(input_left);
        let lr_out = self.lr.process(input_left);
        let rl_out = self.rl.process(input_right);
        let rr_out = self.rr.process(input_right);

        let len = ll_out
            .len()
            .min(lr_out.len())
            .min(rl_out.len())
            .min(rr_out.len());

        let mut output_left = Vec::with_capacity(len);
        let mut output_right = Vec::with_capacity(len);

        for i in 0..len {
            // Combine with width and cross-feed control
            let wet_l = ll_out[i] + self.cross_feed * self.width * rl_out[i];
            let wet_r = rr_out[i] + self.cross_feed * self.width * lr_out[i];

            // Mix with dry signal
            if i < input_left.len() && i < input_right.len() {
                output_left.push(input_left[i] * (1.0 - self.mix) + wet_l * self.mix);
                output_right.push(input_right[i] * (1.0 - self.mix) + wet_r * self.mix);
            } else {
                output_left.push(wet_l * self.mix);
                output_right.push(wet_r * self.mix);
            }
        }

        (output_left, output_right)
    }

    /// Process with M/S option
    pub fn process_ms(
        &mut self,
        input_left: &[Sample],
        input_right: &[Sample],
        ms_amount: f64,
    ) -> (Vec<Sample>, Vec<Sample>) {
        // Convert to M/S
        let ms_amount = ms_amount.clamp(0.0, 1.0);

        let mid: Vec<Sample> = input_left
            .iter()
            .zip(input_right.iter())
            .map(|(&l, &r)| (l + r) * 0.5)
            .collect();

        let side: Vec<Sample> = input_left
            .iter()
            .zip(input_right.iter())
            .map(|(&l, &r)| (l - r) * 0.5)
            .collect();

        // Blend L/R with M/S
        let proc_left: Vec<Sample> = input_left
            .iter()
            .zip(mid.iter())
            .map(|(&lr, &ms)| lr * (1.0 - ms_amount) + ms * ms_amount)
            .collect();

        let proc_right: Vec<Sample> = input_right
            .iter()
            .zip(side.iter())
            .map(|(&lr, &ms)| lr * (1.0 - ms_amount) + ms * ms_amount)
            .collect();

        self.process(&proc_left, &proc_right)
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.ll.latency()
    }

    /// Reset all convolvers
    pub fn reset(&mut self) {
        self.ll.reset();
        self.lr.reset();
        self.rl.reset();
        self.rr.reset();
    }
}

/// Adaptive true stereo convolver
/// Automatically adjusts processing based on IR characteristics
pub struct AdaptiveTrueStereoConvolver {
    /// Main convolver
    convolver: TrueStereoConvolver,
    /// Detected IR characteristics
    characteristics: IrCharacteristics,
    /// Auto width enable
    auto_width: bool,
}

/// Analyzed IR characteristics
#[derive(Debug, Clone, Copy)]
pub struct IrCharacteristics {
    /// Cross-correlation between L and R
    pub correlation: f64,
    /// Detected reverb time (RT60)
    pub rt60: f64,
    /// Early reflection density
    pub er_density: f64,
    /// Suggested stereo width
    pub suggested_width: f64,
}

impl AdaptiveTrueStereoConvolver {
    /// Create with automatic analysis
    pub fn new(ir: &TrueStereoIR, partition_size: usize) -> Self {
        let convolver = TrueStereoConvolver::new(ir, partition_size);
        let characteristics = Self::analyze_ir(ir);

        Self {
            convolver,
            characteristics,
            auto_width: true,
        }
    }

    /// Analyze IR characteristics
    fn analyze_ir(ir: &TrueStereoIR) -> IrCharacteristics {
        // Cross-correlation between LL and RR
        let ll = &ir.ll.samples;
        let rr = &ir.rr.samples;
        let len = ll.len().min(rr.len());

        let mut sum_ll = 0.0;
        let mut sum_rr = 0.0;
        let mut sum_lr = 0.0;
        let mut sum_ll_sq = 0.0;
        let mut sum_rr_sq = 0.0;

        for i in 0..len {
            sum_ll += ll[i];
            sum_rr += rr[i];
            sum_lr += ll[i] * rr[i];
            sum_ll_sq += ll[i] * ll[i];
            sum_rr_sq += rr[i] * rr[i];
        }

        let n = len as f64;
        let correlation = (n * sum_lr - sum_ll * sum_rr)
            / ((n * sum_ll_sq - sum_ll * sum_ll).sqrt() * (n * sum_rr_sq - sum_rr * sum_rr).sqrt()
                + 1e-10);

        // Estimate RT60 from energy decay
        let rt60 = Self::estimate_rt60(&ir.ll.samples, ir.sample_rate);

        // Early reflection density
        let er_density = Self::early_reflection_density(&ir.ll.samples, ir.sample_rate);

        // Suggest width based on correlation
        // High correlation = more mono-compatible, can use more width
        // Low correlation = already wide, reduce width to avoid phase issues
        let suggested_width = 0.5 + correlation.abs() * 0.5;

        IrCharacteristics {
            correlation,
            rt60,
            er_density,
            suggested_width,
        }
    }

    /// Estimate RT60 from energy decay curve
    fn estimate_rt60(samples: &[Sample], sample_rate: f64) -> f64 {
        // Schroeder integration (backward)
        let mut energy: Vec<f64> = samples.iter().map(|s| s * s).collect();

        // Cumulative sum from end
        for i in (0..energy.len() - 1).rev() {
            energy[i] += energy[i + 1];
        }

        // Find -60dB point
        let total = energy[0];
        let threshold = total * 1e-6; // -60dB

        for (i, &e) in energy.iter().enumerate() {
            if e < threshold {
                return i as f64 / sample_rate;
            }
        }

        samples.len() as f64 / sample_rate
    }

    /// Calculate early reflection density
    fn early_reflection_density(samples: &[Sample], sample_rate: f64) -> f64 {
        // Count peaks in first 80ms (early reflections)
        let early_samples = (0.08 * sample_rate) as usize;
        let early = &samples[..early_samples.min(samples.len())];

        let threshold = early.iter().map(|s| s.abs()).fold(0.0, f64::max) * 0.1;

        let mut peaks = 0;
        for i in 1..early.len() - 1 {
            if early[i].abs() > threshold
                && early[i].abs() > early[i - 1].abs()
                && early[i].abs() > early[i + 1].abs()
            {
                peaks += 1;
            }
        }

        peaks as f64 / (early_samples as f64 / sample_rate)
    }

    /// Enable/disable auto width
    pub fn set_auto_width(&mut self, enable: bool) {
        self.auto_width = enable;
        if enable {
            self.convolver
                .set_width(self.characteristics.suggested_width);
        }
    }

    /// Process with adaptive settings
    pub fn process(
        &mut self,
        input_left: &[Sample],
        input_right: &[Sample],
    ) -> (Vec<Sample>, Vec<Sample>) {
        self.convolver.process(input_left, input_right)
    }

    /// Get analyzed characteristics
    pub fn characteristics(&self) -> &IrCharacteristics {
        &self.characteristics
    }

    /// Get inner convolver
    pub fn inner(&mut self) -> &mut TrueStereoConvolver {
        &mut self.convolver
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_true_stereo_ir_creation() {
        let ir = TrueStereoIR::new(
            vec![1.0, 0.5],
            vec![0.2, 0.1],
            vec![0.2, 0.1],
            vec![1.0, 0.5],
            44100.0,
        );

        assert_eq!(ir.max_len(), 2);
    }

    #[test]
    fn test_true_stereo_convolver() {
        let ir = TrueStereoIR::new(
            vec![1.0; 256],
            vec![0.1; 256],
            vec![0.1; 256],
            vec![1.0; 256],
            44100.0,
        );

        // Use small partition size so we get output with small input
        let mut convolver = TrueStereoConvolver::new(&ir, 4);

        // Input must be at least partition_size (fft_size/2 = 2) to get output
        let input_l = vec![1.0, 0.0, 1.0, 0.0];
        let input_r = vec![0.0, 1.0, 0.0, 1.0];

        let (out_l, out_r) = convolver.process(&input_l, &input_r);

        // With partition_size=2 and 4 input samples, we should get 2 output samples
        // (one per completed partition)
        assert!(
            out_l.len() >= 2 || out_r.len() >= 2,
            "Expected output, got out_l.len()={}, out_r.len()={}",
            out_l.len(),
            out_r.len()
        );

        // Verify output is finite
        assert!(out_l.iter().all(|x| x.is_finite()));
        assert!(out_r.iter().all(|x| x.is_finite()));
    }

    #[test]
    fn test_width_control() {
        let ir = TrueStereoIR::new(
            vec![1.0; 128],
            vec![0.5; 128],
            vec![0.5; 128],
            vec![1.0; 128],
            44100.0,
        );

        let mut convolver = TrueStereoConvolver::new(&ir, 64);

        convolver.set_width(0.0);
        assert_eq!(convolver.width, 0.0);

        convolver.set_width(1.5);
        assert_eq!(convolver.width, 1.5);

        convolver.set_width(3.0); // Clamped
        assert_eq!(convolver.width, 2.0);
    }
}
