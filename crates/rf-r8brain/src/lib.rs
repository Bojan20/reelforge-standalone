//! rf-r8brain — Reference-grade sample rate converter
//!
//! Pure Rust port of the r8brain-free-src algorithm by Aleksey Vaneev (Voxengo).
//! Original C++ source: https://github.com/avaneev/r8brain-free-src (MIT license)
//!
//! Multi-stage resampling pipeline:
//! 1. Half-band 2x up/downsample (sparse FIR)
//! 2. FFT-based overlap-save block convolution (anti-aliasing)
//! 3. Polynomial-interpolated sinc fractional delay filters (core innovation)
//! 4. Optional minimum-phase transform (lower latency)
//!
//! Attribution: Sample rate converter designed by Aleksey Vaneev of Voxengo

pub mod kaiser;
pub mod frac_interpolator;
