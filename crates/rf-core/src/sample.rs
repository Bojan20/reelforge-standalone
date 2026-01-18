//! Sample types and audio buffer definitions

use std::simd::{f64x4, f64x8};

/// Type alias for audio samples (always f64 for maximum precision)
pub type Sample = f64;

/// SIMD vector of 4 samples (AVX2/SSE)
pub type Sample4 = f64x4;

/// SIMD vector of 8 samples (AVX-512)
pub type Sample8 = f64x8;

/// Stereo sample pair
#[derive(Debug, Clone, Copy, Default)]
#[repr(C)]
pub struct StereoSample {
    pub left: Sample,
    pub right: Sample,
}

impl StereoSample {
    #[inline]
    pub const fn new(left: Sample, right: Sample) -> Self {
        Self { left, right }
    }

    #[inline]
    pub const fn mono(value: Sample) -> Self {
        Self {
            left: value,
            right: value,
        }
    }

    #[inline]
    pub fn to_mid_side(self) -> MidSideSample {
        MidSideSample {
            mid: (self.left + self.right) * 0.5,
            side: (self.left - self.right) * 0.5,
        }
    }
}

/// Mid/Side sample pair
#[derive(Debug, Clone, Copy, Default)]
#[repr(C)]
pub struct MidSideSample {
    pub mid: Sample,
    pub side: Sample,
}

impl MidSideSample {
    #[inline]
    pub fn to_stereo(self) -> StereoSample {
        StereoSample {
            left: self.mid + self.side,
            right: self.mid - self.side,
        }
    }
}

/// Audio buffer trait for generic buffer operations
pub trait AudioBuffer {
    fn len(&self) -> usize;
    fn is_empty(&self) -> bool {
        self.len() == 0
    }
    fn clear(&mut self);
}

/// Mono audio buffer
#[derive(Debug, Clone)]
pub struct MonoBuffer {
    samples: Vec<Sample>,
}

impl MonoBuffer {
    pub fn new(size: usize) -> Self {
        Self {
            samples: vec![0.0; size],
        }
    }

    #[inline]
    pub fn samples(&self) -> &[Sample] {
        &self.samples
    }

    #[inline]
    pub fn samples_mut(&mut self) -> &mut [Sample] {
        &mut self.samples
    }
}

impl AudioBuffer for MonoBuffer {
    fn len(&self) -> usize {
        self.samples.len()
    }

    fn clear(&mut self) {
        self.samples.fill(0.0);
    }
}

/// Stereo audio buffer (interleaved or split)
#[derive(Debug, Clone)]
pub struct StereoBuffer {
    left: Vec<Sample>,
    right: Vec<Sample>,
}

impl StereoBuffer {
    pub fn new(size: usize) -> Self {
        Self {
            left: vec![0.0; size],
            right: vec![0.0; size],
        }
    }

    #[inline]
    pub fn left(&self) -> &[Sample] {
        &self.left
    }

    #[inline]
    pub fn right(&self) -> &[Sample] {
        &self.right
    }

    #[inline]
    pub fn left_mut(&mut self) -> &mut [Sample] {
        &mut self.left
    }

    #[inline]
    pub fn right_mut(&mut self) -> &mut [Sample] {
        &mut self.right
    }

    #[inline]
    pub fn channels(&self) -> (&[Sample], &[Sample]) {
        (&self.left, &self.right)
    }

    #[inline]
    pub fn channels_mut(&mut self) -> (&mut [Sample], &mut [Sample]) {
        (&mut self.left, &mut self.right)
    }

    /// Process stereo buffer with SIMD (4 samples at a time)
    #[inline]
    pub fn process_simd4<F>(&mut self, mut f: F)
    where
        F: FnMut(Sample4, Sample4) -> (Sample4, Sample4),
    {
        let len = self.left.len();
        let simd_len = len - (len % 4);

        for i in (0..simd_len).step_by(4) {
            let left = Sample4::from_slice(&self.left[i..]);
            let right = Sample4::from_slice(&self.right[i..]);

            let (out_left, out_right) = f(left, right);

            self.left[i..i + 4].copy_from_slice(&out_left.to_array());
            self.right[i..i + 4].copy_from_slice(&out_right.to_array());
        }

        // Handle remaining samples
        for i in simd_len..len {
            let left = Sample4::splat(self.left[i]);
            let right = Sample4::splat(self.right[i]);
            let (out_left, out_right) = f(left, right);
            self.left[i] = out_left[0];
            self.right[i] = out_right[0];
        }
    }
}

impl AudioBuffer for StereoBuffer {
    fn len(&self) -> usize {
        self.left.len()
    }

    fn clear(&mut self) {
        self.left.fill(0.0);
        self.right.fill(0.0);
    }
}
