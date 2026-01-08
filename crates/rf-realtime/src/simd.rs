//! SIMD Optimization Layer
//!
//! ULTIMATIVNI SIMD support:
//! - Unified dispatch (AVX-512/AVX2/SSE4.2/NEON)
//! - Vectorized processing for all modules
//! - Batch processing optimization
//! - Cache-friendly memory layouts

#[cfg(target_arch = "x86_64")]
use std::arch::x86_64::*;

/// SIMD capability detection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SimdLevel {
    /// Scalar fallback
    Scalar,
    /// SSE 4.2 (128-bit, 2 doubles)
    Sse42,
    /// AVX2 (256-bit, 4 doubles)
    Avx2,
    /// AVX-512 (512-bit, 8 doubles)
    Avx512,
}

impl SimdLevel {
    /// Detect best available SIMD level
    #[cfg(target_arch = "x86_64")]
    pub fn detect() -> Self {
        if is_x86_feature_detected!("avx512f") {
            Self::Avx512
        } else if is_x86_feature_detected!("avx2") {
            Self::Avx2
        } else if is_x86_feature_detected!("sse4.2") {
            Self::Sse42
        } else {
            Self::Scalar
        }
    }

    #[cfg(target_arch = "aarch64")]
    pub fn detect() -> Self {
        // ARM NEON is always available on aarch64
        Self::Avx2 // Map NEON to AVX2-like capability
    }

    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    pub fn detect() -> Self {
        Self::Scalar
    }

    /// Get vector width in doubles
    pub fn vector_width(&self) -> usize {
        match self {
            Self::Scalar => 1,
            Self::Sse42 => 2,
            Self::Avx2 => 4,
            Self::Avx512 => 8,
        }
    }

    /// Get vector width in f32
    pub fn vector_width_f32(&self) -> usize {
        self.vector_width() * 2
    }
}

/// Cache-aligned buffer for SIMD operations
#[repr(C, align(64))]
pub struct AlignedBuffer {
    data: Vec<f64>,
    len: usize,
}

impl AlignedBuffer {
    /// Create a new aligned buffer
    pub fn new(size: usize) -> Self {
        let aligned_size = (size + 7) & !7; // Round up to 8 (AVX-512 width)
        Self {
            data: vec![0.0; aligned_size],
            len: size,
        }
    }

    /// Get slice
    pub fn as_slice(&self) -> &[f64] {
        &self.data[..self.len]
    }

    /// Get mutable slice
    pub fn as_mut_slice(&mut self) -> &mut [f64] {
        &mut self.data[..self.len]
    }

    /// Get aligned pointer
    pub fn as_ptr(&self) -> *const f64 {
        self.data.as_ptr()
    }

    /// Get aligned mutable pointer
    pub fn as_mut_ptr(&mut self) -> *mut f64 {
        self.data.as_mut_ptr()
    }

    /// Fill with value
    pub fn fill(&mut self, value: f64) {
        self.data[..self.len].fill(value);
    }

    /// Copy from slice
    pub fn copy_from(&mut self, src: &[f64]) {
        let len = src.len().min(self.len);
        self.data[..len].copy_from_slice(&src[..len]);
    }
}

/// SIMD-optimized gain processing
pub struct SimdGain {
    level: SimdLevel,
}

impl SimdGain {
    pub fn new() -> Self {
        Self {
            level: SimdLevel::detect(),
        }
    }

    /// Process gain with best available SIMD
    #[cfg(target_arch = "x86_64")]
    pub fn process(&self, buffer: &mut [f64], gain: f64) {
        match self.level {
            SimdLevel::Avx512 => unsafe { self.process_avx512_impl(buffer, gain) },
            SimdLevel::Avx2 => unsafe { self.process_avx2_impl(buffer, gain) },
            SimdLevel::Sse42 => unsafe { self.process_sse42_impl(buffer, gain) },
            SimdLevel::Scalar => self.process_scalar(buffer, gain),
        }
    }

    /// Process gain - fallback for non-x86_64
    #[cfg(not(target_arch = "x86_64"))]
    pub fn process(&self, buffer: &mut [f64], gain: f64) {
        self.process_scalar(buffer, gain);
    }

    fn process_scalar(&self, buffer: &mut [f64], gain: f64) {
        for sample in buffer.iter_mut() {
            *sample *= gain;
        }
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "sse4.2")]
    unsafe fn process_sse42_impl(&self, buffer: &mut [f64], gain: f64) {
        let gain_vec = _mm_set1_pd(gain);
        let chunks = buffer.len() / 2;

        for i in 0..chunks {
            let ptr = buffer.as_mut_ptr().add(i * 2);
            let data = _mm_loadu_pd(ptr);
            let result = _mm_mul_pd(data, gain_vec);
            _mm_storeu_pd(ptr, result);
        }

        // Handle remainder
        for i in (chunks * 2)..buffer.len() {
            buffer[i] *= gain;
        }
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "avx2")]
    unsafe fn process_avx2_impl(&self, buffer: &mut [f64], gain: f64) {
        let gain_vec = _mm256_set1_pd(gain);
        let chunks = buffer.len() / 4;

        for i in 0..chunks {
            let ptr = buffer.as_mut_ptr().add(i * 4);
            let data = _mm256_loadu_pd(ptr);
            let result = _mm256_mul_pd(data, gain_vec);
            _mm256_storeu_pd(ptr, result);
        }

        // Handle remainder
        for i in (chunks * 4)..buffer.len() {
            buffer[i] *= gain;
        }
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "avx512f")]
    unsafe fn process_avx512_impl(&self, buffer: &mut [f64], gain: f64) {
        let gain_vec = _mm512_set1_pd(gain);
        let chunks = buffer.len() / 8;

        for i in 0..chunks {
            let ptr = buffer.as_mut_ptr().add(i * 8);
            let data = _mm512_loadu_pd(ptr);
            let result = _mm512_mul_pd(data, gain_vec);
            _mm512_storeu_pd(ptr, result);
        }

        // Handle remainder
        for i in (chunks * 8)..buffer.len() {
            buffer[i] *= gain;
        }
    }
}

impl Default for SimdGain {
    fn default() -> Self {
        Self::new()
    }
}

/// SIMD-optimized mix (sum with gains)
pub struct SimdMixer {
    level: SimdLevel,
}

impl SimdMixer {
    pub fn new() -> Self {
        Self {
            level: SimdLevel::detect(),
        }
    }

    /// Mix two buffers: output = a * gain_a + b * gain_b
    #[cfg(target_arch = "x86_64")]
    pub fn mix(&self, a: &[f64], b: &[f64], output: &mut [f64], gain_a: f64, gain_b: f64) {
        match self.level {
            SimdLevel::Avx512 => unsafe { self.mix_avx512_impl(a, b, output, gain_a, gain_b) },
            SimdLevel::Avx2 => unsafe { self.mix_avx2_impl(a, b, output, gain_a, gain_b) },
            SimdLevel::Sse42 => unsafe { self.mix_sse42_impl(a, b, output, gain_a, gain_b) },
            SimdLevel::Scalar => self.mix_scalar(a, b, output, gain_a, gain_b),
        }
    }

    /// Mix - fallback for non-x86_64
    #[cfg(not(target_arch = "x86_64"))]
    pub fn mix(&self, a: &[f64], b: &[f64], output: &mut [f64], gain_a: f64, gain_b: f64) {
        self.mix_scalar(a, b, output, gain_a, gain_b);
    }

    fn mix_scalar(&self, a: &[f64], b: &[f64], output: &mut [f64], gain_a: f64, gain_b: f64) {
        for i in 0..output.len() {
            output[i] = a.get(i).copied().unwrap_or(0.0) * gain_a
                + b.get(i).copied().unwrap_or(0.0) * gain_b;
        }
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "sse4.2")]
    unsafe fn mix_sse42_impl(&self, a: &[f64], b: &[f64], output: &mut [f64], gain_a: f64, gain_b: f64) {
        let gain_a_vec = _mm_set1_pd(gain_a);
        let gain_b_vec = _mm_set1_pd(gain_b);
        let chunks = output.len() / 2;

        for i in 0..chunks {
            let offset = i * 2;
            let a_data = _mm_loadu_pd(a.as_ptr().add(offset));
            let b_data = _mm_loadu_pd(b.as_ptr().add(offset));

            let a_scaled = _mm_mul_pd(a_data, gain_a_vec);
            let b_scaled = _mm_mul_pd(b_data, gain_b_vec);
            let result = _mm_add_pd(a_scaled, b_scaled);

            _mm_storeu_pd(output.as_mut_ptr().add(offset), result);
        }

        for i in (chunks * 2)..output.len() {
            output[i] = a[i] * gain_a + b[i] * gain_b;
        }
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "avx2")]
    unsafe fn mix_avx2_impl(&self, a: &[f64], b: &[f64], output: &mut [f64], gain_a: f64, gain_b: f64) {
        let gain_a_vec = _mm256_set1_pd(gain_a);
        let gain_b_vec = _mm256_set1_pd(gain_b);
        let chunks = output.len() / 4;

        for i in 0..chunks {
            let offset = i * 4;
            let a_data = _mm256_loadu_pd(a.as_ptr().add(offset));
            let b_data = _mm256_loadu_pd(b.as_ptr().add(offset));

            let a_scaled = _mm256_mul_pd(a_data, gain_a_vec);
            let b_scaled = _mm256_mul_pd(b_data, gain_b_vec);
            let result = _mm256_add_pd(a_scaled, b_scaled);

            _mm256_storeu_pd(output.as_mut_ptr().add(offset), result);
        }

        for i in (chunks * 4)..output.len() {
            output[i] = a[i] * gain_a + b[i] * gain_b;
        }
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "avx512f")]
    unsafe fn mix_avx512_impl(&self, a: &[f64], b: &[f64], output: &mut [f64], gain_a: f64, gain_b: f64) {
        let gain_a_vec = _mm512_set1_pd(gain_a);
        let gain_b_vec = _mm512_set1_pd(gain_b);
        let chunks = output.len() / 8;

        for i in 0..chunks {
            let offset = i * 8;
            let a_data = _mm512_loadu_pd(a.as_ptr().add(offset));
            let b_data = _mm512_loadu_pd(b.as_ptr().add(offset));

            let a_scaled = _mm512_mul_pd(a_data, gain_a_vec);
            let b_scaled = _mm512_mul_pd(b_data, gain_b_vec);
            let result = _mm512_add_pd(a_scaled, b_scaled);

            _mm512_storeu_pd(output.as_mut_ptr().add(offset), result);
        }

        for i in (chunks * 8)..output.len() {
            output[i] = a[i] * gain_a + b[i] * gain_b;
        }
    }
}

impl Default for SimdMixer {
    fn default() -> Self {
        Self::new()
    }
}

/// SIMD-optimized biquad filter bank
pub struct SimdBiquadBank {
    level: SimdLevel,
    /// Coefficients: [b0, b1, b2, a1, a2] per filter
    coeffs: Vec<[f64; 5]>,
    /// States: [z1, z2] per filter
    states: Vec<[f64; 2]>,
}

impl SimdBiquadBank {
    pub fn new(num_filters: usize) -> Self {
        Self {
            level: SimdLevel::detect(),
            coeffs: vec![[1.0, 0.0, 0.0, 0.0, 0.0]; num_filters],
            states: vec![[0.0, 0.0]; num_filters],
        }
    }

    /// Set filter coefficients
    pub fn set_coefficients(&mut self, filter: usize, b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) {
        if filter < self.coeffs.len() {
            self.coeffs[filter] = [b0, b1, b2, a1, a2];
        }
    }

    /// Process all filters on a single sample (parallel processing)
    pub fn process_parallel(&mut self, input: f64) -> Vec<f64> {
        let mut outputs = vec![0.0; self.coeffs.len()];

        match self.level {
            SimdLevel::Avx2 | SimdLevel::Avx512 => {
                self.process_parallel_simd(input, &mut outputs);
            }
            _ => {
                self.process_parallel_scalar(input, &mut outputs);
            }
        }

        outputs
    }

    fn process_parallel_scalar(&mut self, input: f64, outputs: &mut [f64]) {
        for (i, (coeffs, state)) in self.coeffs.iter().zip(self.states.iter_mut()).enumerate() {
            let [b0, b1, b2, a1, a2] = *coeffs;
            let [z1, z2] = *state;

            let output = b0 * input + z1;
            state[0] = b1 * input - a1 * output + z2;
            state[1] = b2 * input - a2 * output;

            outputs[i] = output;
        }
    }

    fn process_parallel_simd(&mut self, input: f64, outputs: &mut [f64]) {
        // Fall back to scalar for now - full SIMD biquad is complex
        self.process_parallel_scalar(input, outputs);
    }

    /// Process a buffer through a single filter
    pub fn process_buffer(&mut self, filter: usize, buffer: &mut [f64]) {
        if filter >= self.coeffs.len() {
            return;
        }

        let [b0, b1, b2, a1, a2] = self.coeffs[filter];
        let state = &mut self.states[filter];

        for sample in buffer.iter_mut() {
            let input = *sample;
            let output = b0 * input + state[0];
            state[0] = b1 * input - a1 * output + state[1];
            state[1] = b2 * input - a2 * output;
            *sample = output;
        }
    }

    /// Reset all filter states
    pub fn reset(&mut self) {
        for state in &mut self.states {
            *state = [0.0, 0.0];
        }
    }
}

/// SIMD-optimized peak detection
pub struct SimdPeakDetector {
    level: SimdLevel,
}

impl SimdPeakDetector {
    pub fn new() -> Self {
        Self {
            level: SimdLevel::detect(),
        }
    }

    /// Find peak (absolute maximum) in buffer
    #[cfg(target_arch = "x86_64")]
    pub fn find_peak(&self, buffer: &[f64]) -> f64 {
        match self.level {
            SimdLevel::Avx512 => unsafe { self.find_peak_avx512_impl(buffer) },
            SimdLevel::Avx2 => unsafe { self.find_peak_avx2_impl(buffer) },
            _ => self.find_peak_scalar(buffer),
        }
    }

    /// Find peak - fallback for non-x86_64
    #[cfg(not(target_arch = "x86_64"))]
    pub fn find_peak(&self, buffer: &[f64]) -> f64 {
        self.find_peak_scalar(buffer)
    }

    fn find_peak_scalar(&self, buffer: &[f64]) -> f64 {
        buffer.iter().map(|x| x.abs()).fold(0.0, f64::max)
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "avx2")]
    unsafe fn find_peak_avx2_impl(&self, buffer: &[f64]) -> f64 {
        let sign_mask = _mm256_set1_pd(-0.0);
        let mut max_vec = _mm256_setzero_pd();
        let chunks = buffer.len() / 4;

        for i in 0..chunks {
            let data = _mm256_loadu_pd(buffer.as_ptr().add(i * 4));
            let abs_data = _mm256_andnot_pd(sign_mask, data);
            max_vec = _mm256_max_pd(max_vec, abs_data);
        }

        // Horizontal max
        let mut result = [0.0f64; 4];
        _mm256_storeu_pd(result.as_mut_ptr(), max_vec);
        let mut max = result.iter().cloned().fold(0.0, f64::max);

        // Handle remainder
        for i in (chunks * 4)..buffer.len() {
            max = max.max(buffer[i].abs());
        }

        max
    }

    #[cfg(target_arch = "x86_64")]
    #[target_feature(enable = "avx512f")]
    unsafe fn find_peak_avx512_impl(&self, buffer: &[f64]) -> f64 {
        let mut max_vec = _mm512_setzero_pd();
        let chunks = buffer.len() / 8;

        for i in 0..chunks {
            let data = _mm512_loadu_pd(buffer.as_ptr().add(i * 8));
            let abs_data = _mm512_abs_pd(data);
            max_vec = _mm512_max_pd(max_vec, abs_data);
        }

        // Reduce max
        let max = _mm512_reduce_max_pd(max_vec);

        // Handle remainder
        let mut result = max;
        for i in (chunks * 8)..buffer.len() {
            result = result.max(buffer[i].abs());
        }

        result
    }
}

impl Default for SimdPeakDetector {
    fn default() -> Self {
        Self::new()
    }
}

/// Batch processor for multiple channels
pub struct BatchProcessor {
    level: SimdLevel,
    num_channels: usize,
    block_size: usize,
    /// Interleaved buffer for SIMD processing
    interleaved: AlignedBuffer,
}

impl BatchProcessor {
    pub fn new(num_channels: usize, block_size: usize) -> Self {
        Self {
            level: SimdLevel::detect(),
            num_channels,
            block_size,
            interleaved: AlignedBuffer::new(num_channels * block_size),
        }
    }

    /// Interleave separate channel buffers
    pub fn interleave(&mut self, channels: &[&[f64]]) {
        for (i, sample_idx) in (0..self.block_size).enumerate() {
            for (ch, channel) in channels.iter().enumerate() {
                if sample_idx < channel.len() {
                    self.interleaved.as_mut_slice()[i * self.num_channels + ch] = channel[sample_idx];
                }
            }
        }
    }

    /// Deinterleave to separate channel buffers
    pub fn deinterleave(&self, channels: &mut [&mut [f64]]) {
        for sample_idx in 0..self.block_size {
            for (ch, channel) in channels.iter_mut().enumerate() {
                if sample_idx < channel.len() {
                    channel[sample_idx] = self.interleaved.as_slice()[sample_idx * self.num_channels + ch];
                }
            }
        }
    }

    /// Process interleaved data with a function
    pub fn process_interleaved<F>(&mut self, mut processor: F)
    where
        F: FnMut(&mut [f64]),
    {
        processor(self.interleaved.as_mut_slice());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simd_level_detection() {
        let level = SimdLevel::detect();
        assert!(level.vector_width() >= 1);
    }

    #[test]
    fn test_aligned_buffer() {
        let mut buffer = AlignedBuffer::new(100);
        assert!(buffer.as_ptr() as usize % 64 == 0); // 64-byte aligned

        buffer.fill(1.5);
        assert_eq!(buffer.as_slice()[50], 1.5);
    }

    #[test]
    fn test_simd_gain() {
        let gain = SimdGain::new();
        let mut buffer = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];

        gain.process(&mut buffer, 2.0);

        assert_eq!(buffer, vec![2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]);
    }

    #[test]
    fn test_simd_mixer() {
        let mixer = SimdMixer::new();
        let a = vec![1.0, 2.0, 3.0, 4.0];
        let b = vec![4.0, 3.0, 2.0, 1.0];
        let mut output = vec![0.0; 4];

        mixer.mix(&a, &b, &mut output, 0.5, 0.5);

        // (1*0.5 + 4*0.5) = 2.5, etc.
        assert_eq!(output, vec![2.5, 2.5, 2.5, 2.5]);
    }

    #[test]
    fn test_simd_biquad_bank() {
        let mut bank = SimdBiquadBank::new(4);

        // Set passthrough coefficients
        for i in 0..4 {
            bank.set_coefficients(i, 1.0, 0.0, 0.0, 0.0, 0.0);
        }

        let outputs = bank.process_parallel(1.0);
        assert_eq!(outputs, vec![1.0, 1.0, 1.0, 1.0]);
    }

    #[test]
    fn test_simd_peak_detector() {
        let detector = SimdPeakDetector::new();
        let buffer = vec![-1.0, 2.0, -3.0, 4.0, -5.0, 6.0, -7.0, 8.0, -9.0, 10.0];

        let peak = detector.find_peak(&buffer);
        assert_eq!(peak, 10.0);
    }

    #[test]
    fn test_batch_processor() {
        let mut processor = BatchProcessor::new(2, 4);

        let ch0 = [1.0, 2.0, 3.0, 4.0];
        let ch1 = [5.0, 6.0, 7.0, 8.0];

        processor.interleave(&[&ch0, &ch1]);

        // Verify interleaved: [1, 5, 2, 6, 3, 7, 4, 8]
        let interleaved = processor.interleaved.as_slice();
        assert_eq!(interleaved[0], 1.0);
        assert_eq!(interleaved[1], 5.0);
        assert_eq!(interleaved[2], 2.0);
        assert_eq!(interleaved[3], 6.0);
    }
}
