//! ONNX inference engine abstraction
//!
//! Provides unified interface using tract (pure Rust) as primary backend.
//! Optional ORT support can be enabled via the `ort-runtime` feature.

use crate::error::{MlError, MlResult};
use std::path::Path;

/// Execution provider for inference
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionProvider {
    /// CPU execution using Tract (pure Rust)
    Cpu,
    /// NVIDIA CUDA (requires ort-runtime feature)
    Cuda,
    /// NVIDIA TensorRT (requires ort-runtime feature)
    TensorRT,
    /// Apple CoreML (requires ort-runtime feature)
    CoreML,
    /// DirectML (Windows, requires ort-runtime feature)
    DirectML,
}

impl ExecutionProvider {
    /// Check if this provider is available on current system
    pub fn is_available(&self) -> bool {
        match self {
            ExecutionProvider::Cpu => true,
            // GPU providers require ort-runtime feature
            #[cfg(feature = "ort-runtime")]
            ExecutionProvider::Cuda => Self::check_cuda(),
            #[cfg(not(feature = "ort-runtime"))]
            ExecutionProvider::Cuda => false,
            #[cfg(feature = "ort-runtime")]
            ExecutionProvider::TensorRT => Self::check_tensorrt(),
            #[cfg(not(feature = "ort-runtime"))]
            ExecutionProvider::TensorRT => false,
            #[cfg(all(feature = "ort-runtime", target_os = "macos"))]
            ExecutionProvider::CoreML => true,
            #[cfg(not(all(feature = "ort-runtime", target_os = "macos")))]
            ExecutionProvider::CoreML => false,
            #[cfg(all(feature = "ort-runtime", target_os = "windows"))]
            ExecutionProvider::DirectML => true,
            #[cfg(not(all(feature = "ort-runtime", target_os = "windows")))]
            ExecutionProvider::DirectML => false,
        }
    }

    #[cfg(feature = "ort-runtime")]
    fn check_cuda() -> bool {
        std::env::var("CUDA_PATH").is_ok()
            || std::path::Path::new("/usr/local/cuda").exists()
    }

    #[cfg(feature = "ort-runtime")]
    fn check_tensorrt() -> bool {
        Self::check_cuda()
            && (std::env::var("TENSORRT_PATH").is_ok()
                || std::path::Path::new("/usr/lib/x86_64-linux-gnu/libnvinfer.so").exists())
    }

    /// Get priority (higher = preferred)
    pub fn priority(&self) -> u32 {
        match self {
            ExecutionProvider::TensorRT => 100,
            ExecutionProvider::Cuda => 90,
            ExecutionProvider::CoreML => 85,
            ExecutionProvider::DirectML => 80,
            ExecutionProvider::Cpu => 10,
        }
    }
}

/// Configuration for inference engine
#[derive(Debug, Clone)]
pub struct InferenceConfig {
    /// Preferred execution providers (in order)
    pub providers: Vec<ExecutionProvider>,
    /// Number of threads for CPU execution
    pub num_threads: usize,
    /// Enable memory optimization
    pub optimize_memory: bool,
    /// Enable graph optimization
    pub optimize_graph: bool,
    /// Device ID for GPU execution
    pub device_id: i32,
    /// Use GPU if available
    pub use_gpu: bool,
    /// Batch size for inference
    pub batch_size: usize,
}

impl Default for InferenceConfig {
    fn default() -> Self {
        Self {
            providers: vec![
                ExecutionProvider::TensorRT,
                ExecutionProvider::Cuda,
                ExecutionProvider::CoreML,
                ExecutionProvider::DirectML,
                ExecutionProvider::Cpu,
            ],
            num_threads: num_cpus::get(),
            optimize_memory: true,
            optimize_graph: true,
            device_id: 0,
            use_gpu: true,
            batch_size: 1,
        }
    }
}

/// Tract model wrapper
struct TractModel {
    model: tract_onnx::prelude::SimplePlan<
        tract_onnx::prelude::TypedFact,
        Box<dyn tract_onnx::prelude::TypedOp>,
        tract_onnx::prelude::Graph<
            tract_onnx::prelude::TypedFact,
            Box<dyn tract_onnx::prelude::TypedOp>,
        >,
    >,
}

/// Unified inference engine
pub struct InferenceEngine {
    /// Active execution provider
    provider: ExecutionProvider,
    /// Tract model (primary backend)
    tract_model: TractModel,
    /// Configuration
    #[allow(dead_code)]
    config: InferenceConfig,
}

impl InferenceEngine {
    /// Create new inference engine with model
    pub fn new<P: AsRef<Path>>(model_path: P, config: InferenceConfig) -> MlResult<Self> {
        let path = model_path.as_ref();

        if !path.exists() {
            return Err(MlError::ModelNotFound {
                path: path.display().to_string(),
            });
        }

        // Find best available provider
        let provider = config
            .providers
            .iter()
            .filter(|p| p.is_available())
            .max_by_key(|p| p.priority())
            .copied()
            .unwrap_or(ExecutionProvider::Cpu);

        log::info!(
            "Using execution provider: {:?} for model {}",
            provider,
            path.display()
        );

        // Load model with Tract
        let model = Self::load_tract_model(path)?;

        Ok(Self {
            provider,
            tract_model: model,
            config,
        })
    }

    /// Load tract model
    fn load_tract_model(path: &Path) -> MlResult<TractModel> {
        use tract_onnx::prelude::*;

        let model = tract_onnx::onnx()
            .model_for_path(path)
            .map_err(|e| MlError::TractError(e.to_string()))?
            .into_optimized()
            .map_err(|e| MlError::TractError(e.to_string()))?
            .into_runnable()
            .map_err(|e| MlError::TractError(e.to_string()))?;

        Ok(TractModel { model })
    }

    /// Run inference with f32 input/output
    pub fn run_f32(
        &self,
        inputs: &[ndarray::ArrayD<f32>],
    ) -> MlResult<Vec<ndarray::ArrayD<f32>>> {
        self.run_tract_f32(&self.tract_model, inputs)
    }

    /// Run inference with Tract
    fn run_tract_f32(
        &self,
        tract: &TractModel,
        inputs: &[ndarray::ArrayD<f32>],
    ) -> MlResult<Vec<ndarray::ArrayD<f32>>> {
        use tract_onnx::prelude::*;

        // Convert inputs to tract tensors
        let tract_inputs: TVec<TValue> = inputs
            .iter()
            .map(|arr| {
                let tensor: Tensor = arr.clone().into();
                tensor.into()
            })
            .collect();

        // Run inference
        let outputs = tract
            .model
            .run(tract_inputs)
            .map_err(|e| MlError::TractError(e.to_string()))?;

        // Convert outputs back to ndarray
        let mut result = Vec::new();
        for output in outputs.iter() {
            let tensor = output
                .to_array_view::<f32>()
                .map_err(|e| MlError::TractError(e.to_string()))?;
            result.push(tensor.to_owned().into_dyn());
        }

        Ok(result)
    }

    /// Get current execution provider
    pub fn provider(&self) -> ExecutionProvider {
        self.provider
    }

    /// Check if using GPU acceleration
    pub fn is_gpu_accelerated(&self) -> bool {
        matches!(
            self.provider,
            ExecutionProvider::Cuda
                | ExecutionProvider::TensorRT
                | ExecutionProvider::CoreML
                | ExecutionProvider::DirectML
        )
    }

    /// Get input shapes for the model (not available for tract)
    pub fn input_shapes(&self) -> MlResult<Vec<Vec<Option<usize>>>> {
        Ok(vec![])
    }

    /// Get output shapes for the model (not available for tract)
    pub fn output_shapes(&self) -> MlResult<Vec<Vec<Option<usize>>>> {
        Ok(vec![])
    }

    /// Run inference with 3D array input, return 4D array output
    /// Input: [batch, channels, samples]
    /// Output: [batch, stems, channels, samples]
    pub fn run_array3(&self, input: &ndarray::Array3<f32>) -> MlResult<ndarray::Array4<f32>> {
        let input_dyn = input.clone().into_dyn();
        let outputs = self.run_f32(&[input_dyn])?;

        if outputs.is_empty() {
            return Err(MlError::InferenceFailed { reason: "No output from model".into() });
        }

        // Convert first output to Array4
        let output = &outputs[0];
        let shape = output.shape();

        if shape.len() != 4 {
            return Err(MlError::InvalidOutputShape {
                expected: "4D tensor [batch, stems, channels, samples]".into(),
                got: format!("{}D tensor {:?}", shape.len(), shape),
            });
        }

        let array4 = output
            .clone()
            .into_dimensionality::<ndarray::Ix4>()
            .map_err(|e| MlError::ProcessingFailed(format!("Shape conversion failed: {}", e)))?;

        Ok(array4)
    }

    /// Run inference with 2D array input (mono audio)
    /// Input: [batch, samples]
    /// Output: [batch, samples]
    pub fn run_array2(&self, input: &ndarray::Array2<f32>) -> MlResult<ndarray::Array2<f32>> {
        let input_dyn = input.clone().into_dyn();
        let outputs = self.run_f32(&[input_dyn])?;

        if outputs.is_empty() {
            return Err(MlError::InferenceFailed { reason: "No output from model".into() });
        }

        let output = &outputs[0];
        let array2 = output
            .clone()
            .into_dimensionality::<ndarray::Ix2>()
            .map_err(|e| MlError::ProcessingFailed(format!("Shape conversion failed: {}", e)))?;

        Ok(array2)
    }

    /// Run inference with multiple 2D arrays (for ERB model)
    pub fn run_multi_array2(
        &self,
        inputs: &[ndarray::Array2<f32>],
    ) -> MlResult<Vec<ndarray::Array2<f32>>> {
        let input_dyns: Vec<ndarray::ArrayD<f32>> =
            inputs.iter().map(|a| a.clone().into_dyn()).collect();

        let outputs = self.run_f32(&input_dyns)?;

        outputs
            .into_iter()
            .map(|out| {
                out.into_dimensionality::<ndarray::Ix2>()
                    .map_err(|e| MlError::ProcessingFailed(format!("Shape conversion: {}", e)))
            })
            .collect()
    }
}

/// Auto-detect best execution provider
pub fn detect_best_provider() -> ExecutionProvider {
    let providers = [
        ExecutionProvider::TensorRT,
        ExecutionProvider::Cuda,
        ExecutionProvider::CoreML,
        ExecutionProvider::DirectML,
        ExecutionProvider::Cpu,
    ];

    providers
        .into_iter()
        .filter(|p| p.is_available())
        .max_by_key(|p| p.priority())
        .unwrap_or(ExecutionProvider::Cpu)
}

/// Get all available execution providers
pub fn available_providers() -> Vec<ExecutionProvider> {
    [
        ExecutionProvider::TensorRT,
        ExecutionProvider::Cuda,
        ExecutionProvider::CoreML,
        ExecutionProvider::DirectML,
        ExecutionProvider::Cpu,
    ]
    .into_iter()
    .filter(|p| p.is_available())
    .collect()
}
