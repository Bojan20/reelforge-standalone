//! GPU Filter Processing - Rust interface for WGSL compute shaders
//!
//! Provides GPU-accelerated audio processing for:
//! - Biquad filter chains (64+ bands)
//! - Multi-band processing with Linkwitz-Riley crossovers
//! - Oversampling (2x, 4x, 8x)
//! - Dynamic EQ
//! - Saturation/waveshaping
//! - Stereo M/S processing

use std::sync::Arc;
use wgpu::{self};
use bytemuck::{Pod, Zeroable};

use crate::common::{GpuContext, VizError, VizResult};

/// Maximum number of filter bands
pub const MAX_GPU_BANDS: usize = 64;

/// Maximum audio buffer size for GPU processing
pub const MAX_BUFFER_SIZE: usize = 65536;

// ============================================================================
// GPU Buffer Types (must match WGSL structs)
// ============================================================================

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct GpuFilterParams {
    pub b0: f32,
    pub b1: f32,
    pub b2: f32,
    pub a1: f32,
    pub a2: f32,
    pub _pad0: f32,
    pub _pad1: f32,
    pub _pad2: f32,
}

impl Default for GpuFilterParams {
    fn default() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            _pad0: 0.0,
            _pad1: 0.0,
            _pad2: 0.0,
        }
    }
}

impl GpuFilterParams {
    /// Create bypass filter
    pub fn bypass() -> Self {
        Self::default()
    }

    /// Create from biquad coefficients
    pub fn from_biquad(b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) -> Self {
        Self {
            b0: b0 as f32,
            b1: b1 as f32,
            b2: b2 as f32,
            a1: a1 as f32,
            a2: a2 as f32,
            ..Default::default()
        }
    }

    /// Peaking EQ filter
    pub fn peaking(freq: f32, gain_db: f32, q: f32, sample_rate: f32) -> Self {
        let a = 10.0_f32.powf(gain_db / 40.0);
        let omega = 2.0 * std::f32::consts::PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * q);

        let b0 = 1.0 + alpha * a;
        let b1 = -2.0 * cos_w;
        let b2 = 1.0 - alpha * a;
        let a0 = 1.0 + alpha / a;
        let a1 = -2.0 * cos_w;
        let a2 = 1.0 - alpha / a;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            ..Default::default()
        }
    }

    /// Low-pass filter
    pub fn lowpass(freq: f32, q: f32, sample_rate: f32) -> Self {
        let omega = 2.0 * std::f32::consts::PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * q);

        let b0 = (1.0 - cos_w) / 2.0;
        let b1 = 1.0 - cos_w;
        let b2 = (1.0 - cos_w) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_w;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            ..Default::default()
        }
    }

    /// High-pass filter
    pub fn highpass(freq: f32, q: f32, sample_rate: f32) -> Self {
        let omega = 2.0 * std::f32::consts::PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * q);

        let b0 = (1.0 + cos_w) / 2.0;
        let b1 = -(1.0 + cos_w);
        let b2 = (1.0 + cos_w) / 2.0;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * cos_w;
        let a2 = 1.0 - alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            ..Default::default()
        }
    }

    /// Low shelf filter
    pub fn low_shelf(freq: f32, gain_db: f32, q: f32, sample_rate: f32) -> Self {
        let a = 10.0_f32.powf(gain_db / 40.0);
        let omega = 2.0 * std::f32::consts::PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * q);
        let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;

        let b0 = a * ((a + 1.0) - (a - 1.0) * cos_w + two_sqrt_a_alpha);
        let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w);
        let b2 = a * ((a + 1.0) - (a - 1.0) * cos_w - two_sqrt_a_alpha);
        let a0 = (a + 1.0) + (a - 1.0) * cos_w + two_sqrt_a_alpha;
        let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_w);
        let a2 = (a + 1.0) + (a - 1.0) * cos_w - two_sqrt_a_alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            ..Default::default()
        }
    }

    /// High shelf filter
    pub fn high_shelf(freq: f32, gain_db: f32, q: f32, sample_rate: f32) -> Self {
        let a = 10.0_f32.powf(gain_db / 40.0);
        let omega = 2.0 * std::f32::consts::PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        let alpha = sin_w / (2.0 * q);
        let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;

        let b0 = a * ((a + 1.0) + (a - 1.0) * cos_w + two_sqrt_a_alpha);
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w);
        let b2 = a * ((a + 1.0) + (a - 1.0) * cos_w - two_sqrt_a_alpha);
        let a0 = (a + 1.0) - (a - 1.0) * cos_w + two_sqrt_a_alpha;
        let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_w);
        let a2 = (a + 1.0) - (a - 1.0) * cos_w - two_sqrt_a_alpha;

        Self {
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            ..Default::default()
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable, Default)]
pub struct GpuFilterState {
    pub z1: f32,
    pub z2: f32,
    pub _pad0: f32,
    pub _pad1: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct GpuProcessConfig {
    pub num_samples: u32,
    pub num_filters: u32,
    pub sample_rate: f32,
    pub block_size: u32,
}

impl Default for GpuProcessConfig {
    fn default() -> Self {
        Self {
            num_samples: 0,
            num_filters: 0,
            sample_rate: 44100.0,
            block_size: 256,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct GpuStereoConfig {
    pub width: f32,
    pub mid_gain: f32,
    pub side_gain: f32,
    pub pan: f32,
}

impl Default for GpuStereoConfig {
    fn default() -> Self {
        Self {
            width: 1.0,
            mid_gain: 1.0,
            side_gain: 1.0,
            pan: 0.0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct GpuSaturationConfig {
    pub drive: f32,
    pub mix: f32,
    pub output_gain: f32,
    pub mode: u32,
}

impl Default for GpuSaturationConfig {
    fn default() -> Self {
        Self {
            drive: 1.0,
            mix: 1.0,
            output_gain: 1.0,
            mode: 0,
        }
    }
}

/// Saturation modes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaturationMode {
    Soft = 0,
    Hard = 1,
    Tube = 2,
    Tape = 3,
}

impl GpuSaturationConfig {
    pub fn new(drive: f32, mix: f32, output_gain: f32, mode: SaturationMode) -> Self {
        Self {
            drive,
            mix,
            output_gain,
            mode: mode as u32,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct GpuDynamicBand {
    // Static params
    pub freq: f32,
    pub gain: f32,
    pub q: f32,
    pub enabled: u32,

    // Dynamic params
    pub threshold: f32,
    pub ratio: f32,
    pub attack_coeff: f32,
    pub release_coeff: f32,

    // State
    pub envelope: f32,
    pub _pad0: f32,
    pub _pad1: f32,
    pub _pad2: f32,
}

impl Default for GpuDynamicBand {
    fn default() -> Self {
        Self {
            freq: 1000.0,
            gain: 0.0,
            q: 1.0,
            enabled: 0,
            threshold: -20.0,
            ratio: 4.0,
            attack_coeff: 0.01,
            release_coeff: 0.001,
            envelope: 0.0,
            _pad0: 0.0,
            _pad1: 0.0,
            _pad2: 0.0,
        }
    }
}

impl GpuDynamicBand {
    pub fn new(freq: f32, gain: f32, q: f32) -> Self {
        Self {
            freq,
            gain,
            q,
            enabled: 1,
            ..Default::default()
        }
    }

    pub fn with_dynamics(mut self, threshold: f32, ratio: f32, attack_ms: f32, release_ms: f32, sample_rate: f32) -> Self {
        self.threshold = threshold;
        self.ratio = ratio;
        self.attack_coeff = (-2.2 / (attack_ms * 0.001 * sample_rate)).exp();
        self.release_coeff = (-2.2 / (release_ms * 0.001 * sample_rate)).exp();
        self
    }
}

// ============================================================================
// GPU Filter Processor
// ============================================================================

/// GPU-accelerated filter processor
pub struct GpuFilterProcessor {
    ctx: Arc<GpuContext>,

    // Compute pipelines
    biquad_pipeline: wgpu::ComputePipeline,
    saturation_pipeline: wgpu::ComputePipeline,
    stereo_pipeline: wgpu::ComputePipeline,

    // Buffers
    input_buffer: wgpu::Buffer,
    output_buffer: wgpu::Buffer,
    filter_params_buffer: wgpu::Buffer,
    filter_states_buffer: wgpu::Buffer,
    config_buffer: wgpu::Buffer,

    // Stereo buffers
    input_left_buffer: wgpu::Buffer,
    input_right_buffer: wgpu::Buffer,
    output_left_buffer: wgpu::Buffer,
    output_right_buffer: wgpu::Buffer,
    stereo_config_buffer: wgpu::Buffer,
    saturation_config_buffer: wgpu::Buffer,

    // Bind groups
    biquad_bind_group: wgpu::BindGroup,
    saturation_bind_group: wgpu::BindGroup,
    stereo_bind_group: wgpu::BindGroup,

    // Staging buffers for CPU readback
    staging_buffer: wgpu::Buffer,
    staging_left_buffer: wgpu::Buffer,
    staging_right_buffer: wgpu::Buffer,

    // Current state
    sample_rate: f32,
    max_samples: usize,
}

impl GpuFilterProcessor {
    pub async fn new(ctx: Arc<GpuContext>, max_samples: usize, sample_rate: f32) -> VizResult<Self> {
        let device = &ctx.device;

        // Load shader
        let shader_source = include_str!("../../../shaders/gpu_filter.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("GPU Filter Shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        // Create buffers
        let input_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Filter Input"),
            size: (max_samples * std::mem::size_of::<f32>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let output_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Filter Output"),
            size: (max_samples * std::mem::size_of::<f32>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let filter_params_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Filter Params"),
            size: (MAX_GPU_BANDS * std::mem::size_of::<GpuFilterParams>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let filter_states_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Filter States"),
            size: (MAX_GPU_BANDS * std::mem::size_of::<GpuFilterState>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let config_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Process Config"),
            size: std::mem::size_of::<GpuProcessConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Stereo buffers
        let stereo_buffer_size = (max_samples * std::mem::size_of::<f32>()) as u64;

        let input_left_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Input L"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let input_right_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Input R"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let output_left_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Output L"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let output_right_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Output R"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let stereo_config_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Config"),
            size: std::mem::size_of::<GpuStereoConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let saturation_config_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Saturation Config"),
            size: std::mem::size_of::<GpuSaturationConfig>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Staging buffers
        let staging_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Filter Staging"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let staging_left_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Staging L"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let staging_right_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("GPU Stereo Staging R"),
            size: stereo_buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Create bind group layouts
        let biquad_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Biquad Bind Group Layout"),
            entries: &[
                // Input buffer
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Output buffer
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Filter params
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Filter states
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Config
                wgpu::BindGroupLayoutEntry {
                    binding: 4,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let stereo_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Stereo Bind Group Layout"),
            entries: &[
                // Stereo config (binding 0 in group 5)
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Input left
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Input right
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Output left
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Output right
                wgpu::BindGroupLayoutEntry {
                    binding: 4,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Saturation config
                wgpu::BindGroupLayoutEntry {
                    binding: 5,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        // Create pipelines
        let biquad_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Biquad Pipeline Layout"),
            bind_group_layouts: &[&biquad_bind_group_layout],
            push_constant_ranges: &[],
        });

        let biquad_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Biquad Filter Pipeline"),
            layout: Some(&biquad_pipeline_layout),
            module: &shader,
            entry_point: Some("biquad_filter_mono"),
            compilation_options: Default::default(),
            cache: None,
        });

        let saturation_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Saturation Pipeline"),
            layout: Some(&biquad_pipeline_layout),
            module: &shader,
            entry_point: Some("saturate"),
            compilation_options: Default::default(),
            cache: None,
        });

        let stereo_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Stereo Pipeline Layout"),
            bind_group_layouts: &[&biquad_bind_group_layout, &stereo_bind_group_layout],
            push_constant_ranges: &[],
        });

        let stereo_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Stereo Process Pipeline"),
            layout: Some(&stereo_pipeline_layout),
            module: &shader,
            entry_point: Some("stereo_process"),
            compilation_options: Default::default(),
            cache: None,
        });

        // Create bind groups
        let biquad_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Biquad Bind Group"),
            layout: &biquad_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: input_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: output_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: filter_params_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: filter_states_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: config_buffer.as_entire_binding(),
                },
            ],
        });

        let saturation_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Saturation Bind Group"),
            layout: &biquad_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: input_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: output_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: filter_params_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: filter_states_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: config_buffer.as_entire_binding(),
                },
            ],
        });

        let stereo_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Stereo Bind Group"),
            layout: &stereo_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: stereo_config_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: input_left_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: input_right_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: output_left_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: output_right_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 5,
                    resource: saturation_config_buffer.as_entire_binding(),
                },
            ],
        });

        Ok(Self {
            ctx,
            biquad_pipeline,
            saturation_pipeline,
            stereo_pipeline,
            input_buffer,
            output_buffer,
            filter_params_buffer,
            filter_states_buffer,
            config_buffer,
            input_left_buffer,
            input_right_buffer,
            output_left_buffer,
            output_right_buffer,
            stereo_config_buffer,
            saturation_config_buffer,
            biquad_bind_group,
            saturation_bind_group,
            stereo_bind_group,
            staging_buffer,
            staging_left_buffer,
            staging_right_buffer,
            sample_rate,
            max_samples,
        })
    }

    /// Create with blocking initialization
    pub fn new_blocking(ctx: Arc<GpuContext>, max_samples: usize, sample_rate: f32) -> VizResult<Self> {
        pollster::block_on(Self::new(ctx, max_samples, sample_rate))
    }

    /// Update filter parameters
    pub fn set_filters(&self, filters: &[GpuFilterParams]) {
        let num_filters = filters.len().min(MAX_GPU_BANDS);
        self.ctx.queue.write_buffer(
            &self.filter_params_buffer,
            0,
            bytemuck::cast_slice(&filters[..num_filters]),
        );
    }

    /// Reset filter states
    pub fn reset_states(&self) {
        let states = vec![GpuFilterState::default(); MAX_GPU_BANDS];
        self.ctx.queue.write_buffer(
            &self.filter_states_buffer,
            0,
            bytemuck::cast_slice(&states),
        );
    }

    /// Process mono audio through filter chain
    pub async fn process_mono(&self, input: &[f32], num_filters: usize) -> VizResult<Vec<f32>> {
        let num_samples = input.len().min(self.max_samples);

        // Upload input
        self.ctx.queue.write_buffer(&self.input_buffer, 0, bytemuck::cast_slice(&input[..num_samples]));

        // Update config
        let config = GpuProcessConfig {
            num_samples: num_samples as u32,
            num_filters: num_filters as u32,
            sample_rate: self.sample_rate,
            block_size: 256,
        };
        self.ctx.queue.write_buffer(&self.config_buffer, 0, bytemuck::bytes_of(&config));

        // Dispatch compute
        let mut encoder = self.ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("GPU Filter Encoder"),
        });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Biquad Filter Pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.biquad_pipeline);
            pass.set_bind_group(0, &self.biquad_bind_group, &[]);
            pass.dispatch_workgroups((num_samples as u32 + 63) / 64, 1, 1);
        }

        // Copy output to staging
        encoder.copy_buffer_to_buffer(
            &self.output_buffer,
            0,
            &self.staging_buffer,
            0,
            (num_samples * std::mem::size_of::<f32>()) as u64,
        );

        self.ctx.queue.submit(std::iter::once(encoder.finish()));

        // Read back result
        let buffer_slice = self.staging_buffer.slice(..);
        let (sender, receiver) = flume::bounded(1);
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });

        self.ctx.device.poll(wgpu::Maintain::Wait);

        receiver.recv_async().await
            .map_err(|e| VizError::Render(e.to_string()))?
            .map_err(|e| VizError::Render(e.to_string()))?;

        let data = buffer_slice.get_mapped_range();
        let result: Vec<f32> = bytemuck::cast_slice(&data[..num_samples * std::mem::size_of::<f32>()]).to_vec();
        drop(data);
        self.staging_buffer.unmap();

        Ok(result)
    }

    /// Process stereo audio with M/S, width, and pan
    pub async fn process_stereo(
        &self,
        left: &[f32],
        right: &[f32],
        config: GpuStereoConfig,
    ) -> VizResult<(Vec<f32>, Vec<f32>)> {
        let num_samples = left.len().min(right.len()).min(self.max_samples);

        // Upload input
        self.ctx.queue.write_buffer(&self.input_left_buffer, 0, bytemuck::cast_slice(&left[..num_samples]));
        self.ctx.queue.write_buffer(&self.input_right_buffer, 0, bytemuck::cast_slice(&right[..num_samples]));
        self.ctx.queue.write_buffer(&self.stereo_config_buffer, 0, bytemuck::bytes_of(&config));

        // Update config
        let process_config = GpuProcessConfig {
            num_samples: num_samples as u32,
            num_filters: 0,
            sample_rate: self.sample_rate,
            block_size: 256,
        };
        self.ctx.queue.write_buffer(&self.config_buffer, 0, bytemuck::bytes_of(&process_config));

        // Dispatch compute
        let mut encoder = self.ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("GPU Stereo Encoder"),
        });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Stereo Process Pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.stereo_pipeline);
            pass.set_bind_group(0, &self.biquad_bind_group, &[]);
            pass.set_bind_group(1, &self.stereo_bind_group, &[]);
            pass.dispatch_workgroups((num_samples as u32 + 63) / 64, 1, 1);
        }

        // Copy output to staging
        let copy_size = (num_samples * std::mem::size_of::<f32>()) as u64;
        encoder.copy_buffer_to_buffer(&self.output_left_buffer, 0, &self.staging_left_buffer, 0, copy_size);
        encoder.copy_buffer_to_buffer(&self.output_right_buffer, 0, &self.staging_right_buffer, 0, copy_size);

        self.ctx.queue.submit(std::iter::once(encoder.finish()));

        // Read back results
        let left_slice = self.staging_left_buffer.slice(..);
        let right_slice = self.staging_right_buffer.slice(..);

        let (sender_l, receiver_l) = flume::bounded(1);
        let (sender_r, receiver_r) = flume::bounded(1);

        left_slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender_l.send(result);
        });
        right_slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender_r.send(result);
        });

        self.ctx.device.poll(wgpu::Maintain::Wait);

        receiver_l.recv_async().await
            .map_err(|e| VizError::Render(e.to_string()))?
            .map_err(|e| VizError::Render(e.to_string()))?;
        receiver_r.recv_async().await
            .map_err(|e| VizError::Render(e.to_string()))?
            .map_err(|e| VizError::Render(e.to_string()))?;

        let left_data = left_slice.get_mapped_range();
        let right_data = right_slice.get_mapped_range();

        let left_result: Vec<f32> = bytemuck::cast_slice(&left_data[..num_samples * std::mem::size_of::<f32>()]).to_vec();
        let right_result: Vec<f32> = bytemuck::cast_slice(&right_data[..num_samples * std::mem::size_of::<f32>()]).to_vec();

        drop(left_data);
        drop(right_data);
        self.staging_left_buffer.unmap();
        self.staging_right_buffer.unmap();

        Ok((left_result, right_result))
    }

    /// Process with saturation
    pub async fn process_saturation(&self, input: &[f32], config: GpuSaturationConfig) -> VizResult<Vec<f32>> {
        let num_samples = input.len().min(self.max_samples);

        // Upload input
        self.ctx.queue.write_buffer(&self.input_buffer, 0, bytemuck::cast_slice(&input[..num_samples]));
        self.ctx.queue.write_buffer(&self.saturation_config_buffer, 0, bytemuck::bytes_of(&config));

        // Update config
        let process_config = GpuProcessConfig {
            num_samples: num_samples as u32,
            num_filters: 0,
            sample_rate: self.sample_rate,
            block_size: 256,
        };
        self.ctx.queue.write_buffer(&self.config_buffer, 0, bytemuck::bytes_of(&process_config));

        // Dispatch compute
        let mut encoder = self.ctx.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("GPU Saturation Encoder"),
        });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Saturation Pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.saturation_pipeline);
            pass.set_bind_group(0, &self.saturation_bind_group, &[]);
            pass.dispatch_workgroups((num_samples as u32 + 63) / 64, 1, 1);
        }

        // Copy output to staging
        encoder.copy_buffer_to_buffer(
            &self.output_buffer,
            0,
            &self.staging_buffer,
            0,
            (num_samples * std::mem::size_of::<f32>()) as u64,
        );

        self.ctx.queue.submit(std::iter::once(encoder.finish()));

        // Read back result
        let buffer_slice = self.staging_buffer.slice(..);
        let (sender, receiver) = flume::bounded(1);
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });

        self.ctx.device.poll(wgpu::Maintain::Wait);

        receiver.recv_async().await
            .map_err(|e| VizError::Render(e.to_string()))?
            .map_err(|e| VizError::Render(e.to_string()))?;

        let data = buffer_slice.get_mapped_range();
        let result: Vec<f32> = bytemuck::cast_slice(&data[..num_samples * std::mem::size_of::<f32>()]).to_vec();
        drop(data);
        self.staging_buffer.unmap();

        Ok(result)
    }
}

// ============================================================================
// EQ Preset Builder for GPU
// ============================================================================

/// Build GPU filter chain from EQ settings
pub struct GpuEqBuilder {
    filters: Vec<GpuFilterParams>,
    sample_rate: f32,
}

impl GpuEqBuilder {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            filters: Vec::new(),
            sample_rate,
        }
    }

    /// Add peaking EQ band
    pub fn add_peak(&mut self, freq: f32, gain_db: f32, q: f32) -> &mut Self {
        self.filters.push(GpuFilterParams::peaking(freq, gain_db, q, self.sample_rate));
        self
    }

    /// Add low shelf
    pub fn add_low_shelf(&mut self, freq: f32, gain_db: f32, q: f32) -> &mut Self {
        self.filters.push(GpuFilterParams::low_shelf(freq, gain_db, q, self.sample_rate));
        self
    }

    /// Add high shelf
    pub fn add_high_shelf(&mut self, freq: f32, gain_db: f32, q: f32) -> &mut Self {
        self.filters.push(GpuFilterParams::high_shelf(freq, gain_db, q, self.sample_rate));
        self
    }

    /// Add low-pass filter
    pub fn add_lowpass(&mut self, freq: f32, q: f32) -> &mut Self {
        self.filters.push(GpuFilterParams::lowpass(freq, q, self.sample_rate));
        self
    }

    /// Add high-pass filter
    pub fn add_highpass(&mut self, freq: f32, q: f32) -> &mut Self {
        self.filters.push(GpuFilterParams::highpass(freq, q, self.sample_rate));
        self
    }

    /// Build filter array
    pub fn build(self) -> Vec<GpuFilterParams> {
        self.filters
    }

    /// Get number of filters
    pub fn len(&self) -> usize {
        self.filters.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.filters.is_empty()
    }
}
