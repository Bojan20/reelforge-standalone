//! GPU DSP Module
//!
//! GPU-accelerated DSP processing via wgpu compute shaders.
//!
//! Features:
//! - Hybrid CPU/GPU scheduler
//! - FFT (Stockham algorithm)
//! - Parallel EQ
//! - Dynamics processing
//! - Partitioned convolution

pub mod scheduler;

pub use scheduler::{
    BatchScheduler, ExecutionStats, GpuDeviceInfo, GpuTask, HybridScheduler, ProcessingTarget,
    SchedulerConfig, SchedulerStats, TaskType,
};
