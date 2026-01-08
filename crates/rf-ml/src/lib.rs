//! # ReelForge ML/AI Processing Suite
//!
//! State-of-the-art neural network audio processing:
//! - Neural Denoising (DeepFilterNet3, FRCRN)
//! - Stem Separation (HTDemucs v4)
//! - Speech Enhancement (aTENNuate SSM)
//! - EQ Matching (Spectral Transfer)
//! - Intelligent Audio Assistant
//!
//! ## Architecture
//!
//! Uses ONNX Runtime (`ort`) as primary inference engine with:
//! - CUDA/TensorRT acceleration on NVIDIA GPUs
//! - CoreML acceleration on Apple Silicon
//! - Pure Rust `tract` fallback for CPU/WASM
//!
//! ## Real-time Considerations
//!
//! All processors designed for low-latency operation:
//! - DeepFilterNet: ~10ms latency
//! - aTENNuate: ~5ms latency
//! - HTDemucs: Offline only (segment-based)

// Many internal items don't need docs
#![allow(missing_docs)]
#![allow(dead_code)]
// ONNX Runtime feature detection
#![allow(unexpected_cfgs)]

pub mod assistant;
pub mod denoise;
pub mod enhance;
pub mod mastering;
pub mod r#match;
pub mod separation;

mod buffer;
mod error;
mod inference;

pub use buffer::{AudioFrame, FrameBuffer};
pub use error::{MlError, MlResult};
pub use inference::{ExecutionProvider, InferenceConfig, InferenceEngine};

/// ML model registry paths
pub mod models {
    /// DeepFilterNet3 ONNX model
    pub const DEEP_FILTER_NET: &str = "models/deepfilternet3.onnx";

    /// HTDemucs v4 encoder
    pub const HTDEMUCS_ENCODER: &str = "models/htdemucs_encoder.onnx";

    /// HTDemucs v4 transformer
    pub const HTDEMUCS_TRANSFORMER: &str = "models/htdemucs_transformer.onnx";

    /// HTDemucs v4 decoder
    pub const HTDEMUCS_DECODER: &str = "models/htdemucs_decoder.onnx";

    /// aTENNuate SSM model
    pub const ATENNUATE: &str = "models/atennuate_ssm.onnx";

    /// Genre classifier
    pub const GENRE_CLASSIFIER: &str = "models/genre_classifier.onnx";

    /// Multi-pitch estimator
    pub const PITCH_ESTIMATOR: &str = "models/pitch_estimator.onnx";
}

/// Sample rates commonly used by ML models
pub mod sample_rates {
    /// DeepFilterNet sample rate
    pub const DEEP_FILTER: u32 = 48000;

    /// HTDemucs sample rate
    pub const HTDEMUCS: u32 = 44100;

    /// aTENNuate sample rate
    pub const ATENNUATE: u32 = 48000;
}

/// Frame sizes for streaming processing
pub mod frame_sizes {
    /// DeepFilterNet frame (10ms @ 48kHz)
    pub const DEEP_FILTER: usize = 480;

    /// aTENNuate frame (5.3ms @ 48kHz)
    pub const ATENNUATE: usize = 256;

    /// Default FFT size for spectral processing
    pub const FFT_DEFAULT: usize = 2048;

    /// Large FFT for high-quality analysis
    pub const FFT_LARGE: usize = 4096;
}
