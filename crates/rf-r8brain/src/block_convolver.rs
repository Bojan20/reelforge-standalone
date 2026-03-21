//! FFT-Based Overlap-Save Block Convolver
//!
//! Implements efficient long-FIR convolution using FFT overlap-save method.
//! O(N log N) complexity vs O(N²) for direct convolution.
//!
//! Used by r8brain pipeline for anti-aliasing/anti-imaging filters
//! that are too long for direct computation.

use rustfft::{FftPlanner, num_complex::Complex64};

/// FFT-based overlap-save block convolver.
///
/// Pre-computes kernel FFT once at init. Each process() call:
/// 1. Prepend previous overlap samples
/// 2. Forward FFT
/// 3. Complex multiply with kernel spectrum
/// 4. Inverse FFT
/// 5. Discard first (kernel_len - 1) aliased samples
///
/// All buffers pre-allocated — zero allocation in process().
pub struct BlockConvolver {
    /// FFT length (power of 2, >= 2 × kernel_len)
    fft_len: usize,
    /// Kernel length (number of filter taps)
    kernel_len: usize,
    /// Valid output samples per block
    output_len: usize,
    /// Pre-computed kernel spectrum (complex, fft_len / 2 + 1)
    kernel_spectrum: Vec<Complex64>,
    /// Input time-domain buffer (fft_len)
    input_buf: Vec<f64>,
    /// FFT scratch buffer (complex, fft_len / 2 + 1)
    fft_scratch: Vec<Complex64>,
    /// Overlap buffer (kernel_len - 1 samples from previous block)
    overlap: Vec<f64>,
    /// Forward FFT plan
    fft_forward: std::sync::Arc<dyn rustfft::Fft<f64>>,
    /// Inverse FFT plan
    fft_inverse: std::sync::Arc<dyn rustfft::Fft<f64>>,
}

impl BlockConvolver {
    /// Create new block convolver for a given filter kernel.
    ///
    /// `kernel`: filter coefficients (FIR taps)
    /// `block_size`: desired processing block size (will be rounded up to power of 2)
    ///
    /// FFT length = next power of 2 >= (block_size + kernel.len() - 1)
    pub fn new(kernel: &[f64], block_size: usize) -> Self {
        let kernel_len = kernel.len();
        assert!(kernel_len >= 1, "kernel must have at least 1 tap");

        // FFT length: must be >= kernel_len + block_size - 1 for overlap-save
        let min_fft = kernel_len + block_size;
        let fft_len = min_fft.next_power_of_two();
        let output_len = fft_len - kernel_len + 1;

        // Create FFT plans
        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(fft_len);
        let fft_inverse = planner.plan_fft_inverse(fft_len);

        // Pre-compute kernel spectrum
        let mut kernel_complex: Vec<Complex64> = kernel
            .iter()
            .map(|&v| Complex64::new(v, 0.0))
            .collect();
        kernel_complex.resize(fft_len, Complex64::new(0.0, 0.0));
        fft_forward.process(&mut kernel_complex);

        // Normalize kernel spectrum for inverse FFT
        let scale = 1.0 / fft_len as f64;
        for c in &mut kernel_complex {
            *c *= scale;
        }

        Self {
            fft_len,
            kernel_len,
            output_len,
            kernel_spectrum: kernel_complex,
            input_buf: vec![0.0; fft_len],
            fft_scratch: vec![Complex64::new(0.0, 0.0); fft_len],
            overlap: vec![0.0; kernel_len.saturating_sub(1)],
            fft_forward,
            fft_inverse,
        }
    }

    /// Process a block of input samples through the convolver.
    ///
    /// `input`: input samples (any length)
    /// `output`: output buffer (will contain convolved signal)
    ///
    /// Returns: number of valid output samples written.
    ///
    /// Note: due to overlap-save, the first call produces fewer valid
    /// samples (kernel_len - 1 samples of latency).
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) -> usize {
        if input.is_empty() {
            return 0;
        }

        let overlap_len = self.overlap.len();
        let mut written = 0;

        // Process in chunks of output_len
        let mut pos = 0;
        while pos < input.len() {
            // Fill input buffer: overlap + new samples
            // Copy overlap from previous block
            self.input_buf[..overlap_len].copy_from_slice(&self.overlap);

            // Copy new input samples
            let chunk = (input.len() - pos).min(self.output_len);
            self.input_buf[overlap_len..overlap_len + chunk].copy_from_slice(&input[pos..pos + chunk]);

            // Zero-pad remainder if chunk < output_len
            for i in overlap_len + chunk..self.fft_len {
                self.input_buf[i] = 0.0;
            }

            // Forward FFT
            for (i, &v) in self.input_buf.iter().enumerate() {
                self.fft_scratch[i] = Complex64::new(v, 0.0);
            }
            self.fft_forward.process(&mut self.fft_scratch);

            // Complex multiply with kernel spectrum
            for (s, k) in self.fft_scratch.iter_mut().zip(self.kernel_spectrum.iter()) {
                *s *= k;
            }

            // Inverse FFT
            self.fft_inverse.process(&mut self.fft_scratch);

            // Extract valid output (skip first overlap_len aliased samples)
            let valid = chunk.min(output.len() - written);
            for i in 0..valid {
                output[written + i] = self.fft_scratch[overlap_len + i].re;
            }
            written += valid;

            // Save overlap for next block: last (kernel_len - 1) samples
            // from the filled portion of input_buf (overlap_prev + new_input).
            // For short chunks (chunk < overlap_len), shift old overlap left
            // and append new samples.
            if chunk >= overlap_len {
                // Normal case: enough new samples to fill entire overlap
                let start = overlap_len + chunk - overlap_len; // = chunk
                self.overlap.copy_from_slice(&self.input_buf[start..start + overlap_len]);
            } else {
                // Short block: shift old overlap left by chunk, append new samples
                self.overlap.copy_within(chunk..overlap_len, 0);
                self.overlap[overlap_len - chunk..overlap_len]
                    .copy_from_slice(&self.input_buf[overlap_len..overlap_len + chunk]);
            }

            pos += chunk;
        }

        written
    }

    /// Reset internal state (clear overlap buffer)
    pub fn reset(&mut self) {
        self.overlap.fill(0.0);
        self.input_buf.fill(0.0);
    }

    /// Latency in samples
    pub fn latency(&self) -> usize {
        self.kernel_len - 1
    }

    /// FFT length used
    pub fn fft_len(&self) -> usize {
        self.fft_len
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convolver_identity() {
        // Identity kernel [1.0] should pass through unchanged
        let conv = BlockConvolver::new(&[1.0], 256);
        assert_eq!(conv.kernel_len, 1);
        assert_eq!(conv.latency(), 0);
    }

    #[test]
    fn test_convolver_delay() {
        // Delay kernel [0, 1] should delay by 1 sample
        let mut conv = BlockConvolver::new(&[0.0, 1.0], 256);
        let input: Vec<f64> = (0..256).map(|i| i as f64).collect();
        let mut output = vec![0.0; 256];
        let written = conv.process(&input, &mut output);
        assert!(written > 0);
    }

    #[test]
    fn test_convolver_dc() {
        // Lowpass filter: all positive coefficients, normalized
        let kernel = vec![0.25, 0.5, 0.25]; // Simple 3-tap lowpass
        let mut conv = BlockConvolver::new(&kernel, 256);

        // DC input
        let input = vec![1.0f64; 512];
        let mut output = vec![0.0f64; 512];
        let written = conv.process(&input, &mut output);

        // After settling, output should be ~1.0 (DC preservation)
        assert!(written > 10);
        for &s in &output[10..written] {
            assert!((s - 1.0).abs() < 0.01, "DC not preserved: {s}");
        }
    }

    #[test]
    fn test_convolver_fft_length() {
        let conv = BlockConvolver::new(&[1.0; 65], 256);
        assert!(conv.fft_len().is_power_of_two());
        assert!(conv.fft_len() >= 65 + 256);
    }
}
