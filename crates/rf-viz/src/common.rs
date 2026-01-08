//! Common GPU utilities for visualization

use std::sync::Arc;
use thiserror::Error;
use wgpu;

/// Visualization errors
#[derive(Error, Debug)]
pub enum VizError {
    #[error("GPU initialization failed: {0}")]
    GpuInit(String),
    #[error("Shader compilation failed: {0}")]
    Shader(String),
    #[error("Buffer creation failed: {0}")]
    Buffer(String),
    #[error("Render failed: {0}")]
    Render(String),
}

pub type VizResult<T> = Result<T, VizError>;

/// Shared GPU context for all visualizations
pub struct GpuContext {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pub adapter_info: wgpu::AdapterInfo,
}

impl GpuContext {
    /// Create GPU context (async)
    pub async fn new() -> VizResult<Self> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: None,
                force_fallback_adapter: false,
            })
            .await
            .ok_or_else(|| VizError::GpuInit("No suitable GPU adapter found".into()))?;

        let adapter_info = adapter.get_info();
        log::info!(
            "Using GPU: {} ({:?})",
            adapter_info.name,
            adapter_info.backend
        );

        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("ReelForge Viz Device"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
                    memory_hints: wgpu::MemoryHints::Performance,
                },
                None,
            )
            .await
            .map_err(|e| VizError::GpuInit(e.to_string()))?;

        Ok(Self {
            device: Arc::new(device),
            queue: Arc::new(queue),
            adapter_info,
        })
    }

    /// Create GPU context (blocking)
    pub fn new_blocking() -> VizResult<Self> {
        pollster::block_on(Self::new())
    }
}

/// Color in linear sRGB (for GPU)
#[repr(C)]
#[derive(Clone, Copy, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Color {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Color {
    pub const fn new(r: f32, g: f32, b: f32, a: f32) -> Self {
        Self { r, g, b, a }
    }

    /// From hex color (e.g., 0x4A9EFF)
    pub fn from_hex(hex: u32) -> Self {
        let r = ((hex >> 16) & 0xFF) as f32 / 255.0;
        let g = ((hex >> 8) & 0xFF) as f32 / 255.0;
        let b = (hex & 0xFF) as f32 / 255.0;
        Self { r, g, b, a: 1.0 }
    }

    pub fn with_alpha(self, a: f32) -> Self {
        Self { a, ..self }
    }

    // ReelForge theme colors
    pub const BLUE: Self = Self::new(0.290, 0.620, 1.0, 1.0); // #4A9EFF
    pub const ORANGE: Self = Self::new(1.0, 0.565, 0.251, 1.0); // #FF9040
    pub const GREEN: Self = Self::new(0.251, 1.0, 0.565, 1.0); // #40FF90
    pub const RED: Self = Self::new(1.0, 0.251, 0.376, 1.0); // #FF4060
    pub const CYAN: Self = Self::new(0.251, 0.784, 1.0, 1.0); // #40C8FF
}

/// Viewport for rendering
#[repr(C)]
#[derive(Clone, Copy, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Viewport {
    pub width: f32,
    pub height: f32,
    pub scale: f32,
    pub _padding: f32,
}

impl Viewport {
    pub fn new(width: f32, height: f32, scale: f32) -> Self {
        Self {
            width,
            height,
            scale,
            _padding: 0.0,
        }
    }
}
