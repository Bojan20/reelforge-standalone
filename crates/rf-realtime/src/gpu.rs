//! GPU Compute Integration
//!
//! ULTIMATIVNI GPU support:
//! - wgpu compute pipeline
//! - GPU FFT for all spectral operations
//! - GPU convolution for large IRs
//! - Async CPU↔GPU data transfer

use bytemuck::{Pod, Zeroable};
use std::sync::Arc;
use wgpu::{BindGroup, Buffer, ComputePipeline, Device, Queue, ShaderModule};

/// GPU compute context
pub struct GpuContext {
    pub device: Arc<Device>,
    pub queue: Arc<Queue>,
}

impl GpuContext {
    /// Create GPU context (async)
    pub async fn new() -> Option<Self> {
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
            .await?;

        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("ReelForge GPU"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
                    memory_hints: wgpu::MemoryHints::Performance,
                },
                None,
            )
            .await
            .ok()?;

        Some(Self {
            device: Arc::new(device),
            queue: Arc::new(queue),
        })
    }

    /// Create compute shader module
    pub fn create_shader(&self, source: &str) -> ShaderModule {
        self.device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("Compute Shader"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            })
    }

    /// Create buffer
    pub fn create_buffer(&self, size: u64, usage: wgpu::BufferUsages) -> Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size,
            usage,
            mapped_at_creation: false,
        })
    }
}

/// GPU FFT processor
pub struct GpuFft {
    context: Arc<GpuContext>,
    pipeline: ComputePipeline,
    input_buffer: Buffer,
    output_buffer: Buffer,
    params_buffer: Buffer,
    bind_group: BindGroup,
    fft_size: usize,
}

/// FFT parameters (uniform buffer)
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct FftParams {
    n: u32,
    log2_n: u32,
    inverse: u32,
    _padding: u32,
}

impl GpuFft {
    /// Create GPU FFT processor
    pub fn new(context: Arc<GpuContext>, fft_size: usize) -> Self {
        let shader_source = include_str!("shaders/fft.wgsl");
        let shader = context.create_shader(shader_source);

        // Create pipeline layout
        let bind_group_layout =
            context
                .device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("FFT Bind Group Layout"),
                    entries: &[
                        wgpu::BindGroupLayoutEntry {
                            binding: 0,
                            visibility: wgpu::ShaderStages::COMPUTE,
                            ty: wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Storage { read_only: false },
                                has_dynamic_offset: false,
                                min_binding_size: None,
                            },
                            count: None,
                        },
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
                        wgpu::BindGroupLayoutEntry {
                            binding: 2,
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

        let pipeline_layout =
            context
                .device
                .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                    label: Some("FFT Pipeline Layout"),
                    bind_group_layouts: &[&bind_group_layout],
                    push_constant_ranges: &[],
                });

        let pipeline = context
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("FFT Pipeline"),
                layout: Some(&pipeline_layout),
                module: &shader,
                entry_point: Some("fft_radix2"),
                compilation_options: Default::default(),
                cache: None,
            });

        // Create buffers (complex f32: 2 * 4 bytes per sample)
        let buffer_size = (fft_size * 2 * 4) as u64;

        let input_buffer = context.create_buffer(
            buffer_size,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );

        let output_buffer = context.create_buffer(
            buffer_size,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );

        let params_buffer = context.create_buffer(
            std::mem::size_of::<FftParams>() as u64,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        );

        let bind_group = context
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("FFT Bind Group"),
                layout: &bind_group_layout,
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
                        resource: params_buffer.as_entire_binding(),
                    },
                ],
            });

        Self {
            context,
            pipeline,
            input_buffer,
            output_buffer,
            params_buffer,
            bind_group,
            fft_size,
        }
    }

    /// Compute forward FFT
    pub fn forward(&self, input: &[f32]) -> Vec<f32> {
        self.compute(input, false)
    }

    /// Compute inverse FFT
    pub fn inverse(&self, input: &[f32]) -> Vec<f32> {
        self.compute(input, true)
    }

    fn compute(&self, input: &[f32], inverse: bool) -> Vec<f32> {
        // Upload input data
        self.context
            .queue
            .write_buffer(&self.input_buffer, 0, bytemuck::cast_slice(input));

        // Upload parameters
        let log2_n = (self.fft_size as f32).log2() as u32;
        let params = FftParams {
            n: self.fft_size as u32,
            log2_n,
            inverse: if inverse { 1 } else { 0 },
            _padding: 0,
        };
        self.context
            .queue
            .write_buffer(&self.params_buffer, 0, bytemuck::bytes_of(&params));

        // Create command encoder
        let mut encoder =
            self.context
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("FFT Encoder"),
                });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("FFT Pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);

            // Dispatch: one workgroup per butterfly stage
            let workgroups = (self.fft_size / 256).max(1) as u32;
            pass.dispatch_workgroups(workgroups, 1, 1);
        }

        // Submit and wait
        self.context.queue.submit(std::iter::once(encoder.finish()));

        // Read back results (synchronous for simplicity)
        let output_slice = self.output_buffer.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();

        output_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });

        self.context.device.poll(wgpu::Maintain::Wait);
        rx.recv().unwrap().unwrap();

        let data = output_slice.get_mapped_range();
        let result: Vec<f32> = bytemuck::cast_slice(&data).to_vec();

        drop(data);
        self.output_buffer.unmap();

        result
    }
}

/// GPU Convolution processor
pub struct GpuConvolution {
    context: Arc<GpuContext>,
    pipeline: ComputePipeline,
    audio_buffer: Buffer,
    ir_buffer: Buffer,
    output_buffer: Buffer,
    params_buffer: Buffer,
    bind_group: BindGroup,
    ir_length: usize,
}

/// Convolution parameters
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct ConvParams {
    ir_length: u32,
    audio_length: u32,
    _padding: [u32; 2],
}

impl GpuConvolution {
    /// Create GPU convolution processor
    pub fn new(context: Arc<GpuContext>, max_ir_length: usize, max_audio_length: usize) -> Self {
        let shader_source = include_str!("shaders/convolution.wgsl");
        let shader = context.create_shader(shader_source);

        let bind_group_layout =
            context
                .device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("Convolution Bind Group Layout"),
                    entries: &[
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
                        wgpu::BindGroupLayoutEntry {
                            binding: 2,
                            visibility: wgpu::ShaderStages::COMPUTE,
                            ty: wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Storage { read_only: false },
                                has_dynamic_offset: false,
                                min_binding_size: None,
                            },
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 3,
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

        let pipeline_layout =
            context
                .device
                .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                    label: Some("Convolution Pipeline Layout"),
                    bind_group_layouts: &[&bind_group_layout],
                    push_constant_ranges: &[],
                });

        let pipeline = context
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("Convolution Pipeline"),
                layout: Some(&pipeline_layout),
                module: &shader,
                entry_point: Some("convolve"),
                compilation_options: Default::default(),
                cache: None,
            });

        let audio_buffer = context.create_buffer(
            (max_audio_length * 4) as u64,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );

        let ir_buffer = context.create_buffer(
            (max_ir_length * 4) as u64,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );

        let output_buffer = context.create_buffer(
            ((max_audio_length + max_ir_length) * 4) as u64,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );

        let params_buffer = context.create_buffer(
            std::mem::size_of::<ConvParams>() as u64,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        );

        let bind_group = context
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("Convolution Bind Group"),
                layout: &bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: audio_buffer.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: ir_buffer.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: output_buffer.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: params_buffer.as_entire_binding(),
                    },
                ],
            });

        Self {
            context,
            pipeline,
            audio_buffer,
            ir_buffer,
            output_buffer,
            params_buffer,
            bind_group,
            ir_length: max_ir_length,
        }
    }

    /// Set impulse response
    pub fn set_ir(&self, ir: &[f32]) {
        self.context
            .queue
            .write_buffer(&self.ir_buffer, 0, bytemuck::cast_slice(ir));
    }

    /// Convolve audio with IR
    pub fn convolve(&self, audio: &[f32]) -> Vec<f32> {
        // Upload audio
        self.context
            .queue
            .write_buffer(&self.audio_buffer, 0, bytemuck::cast_slice(audio));

        // Upload parameters
        let params = ConvParams {
            ir_length: self.ir_length as u32,
            audio_length: audio.len() as u32,
            _padding: [0; 2],
        };
        self.context
            .queue
            .write_buffer(&self.params_buffer, 0, bytemuck::bytes_of(&params));

        // Dispatch
        let mut encoder =
            self.context
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("Convolution Encoder"),
                });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Convolution Pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);

            let output_len = audio.len() + self.ir_length - 1;
            let workgroups = ((output_len + 255) / 256) as u32;
            pass.dispatch_workgroups(workgroups, 1, 1);
        }

        self.context.queue.submit(std::iter::once(encoder.finish()));

        // Read back
        let output_len = audio.len() + self.ir_length - 1;
        let output_slice = self.output_buffer.slice(0..(output_len * 4) as u64);
        let (tx, rx) = std::sync::mpsc::channel();

        output_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });

        self.context.device.poll(wgpu::Maintain::Wait);
        rx.recv().unwrap().unwrap();

        let data = output_slice.get_mapped_range();
        let result: Vec<f32> = bytemuck::cast_slice(&data).to_vec();

        drop(data);
        self.output_buffer.unmap();

        result
    }
}

/// GPU EQ processor (parallel biquads)
pub struct GpuEq {
    context: Arc<GpuContext>,
    pipeline: ComputePipeline,
    audio_buffer: Buffer,
    coeffs_buffer: Buffer,
    states_buffer: Buffer,
    bind_group: BindGroup,
    num_bands: usize,
}

/// Biquad coefficients
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct GpuBiquadCoeffs {
    pub b0: f32,
    pub b1: f32,
    pub b2: f32,
    pub a1: f32,
    pub a2: f32,
    pub enabled: u32,
    pub _padding: [u32; 2],
}

impl GpuEq {
    /// Create GPU EQ processor
    pub fn new(context: Arc<GpuContext>, num_bands: usize, block_size: usize) -> Self {
        let shader_source = include_str!("shaders/eq.wgsl");
        let shader = context.create_shader(shader_source);

        let bind_group_layout =
            context
                .device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("EQ Bind Group Layout"),
                    entries: &[
                        wgpu::BindGroupLayoutEntry {
                            binding: 0,
                            visibility: wgpu::ShaderStages::COMPUTE,
                            ty: wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Storage { read_only: false },
                                has_dynamic_offset: false,
                                min_binding_size: None,
                            },
                            count: None,
                        },
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
                        wgpu::BindGroupLayoutEntry {
                            binding: 2,
                            visibility: wgpu::ShaderStages::COMPUTE,
                            ty: wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Storage { read_only: false },
                                has_dynamic_offset: false,
                                min_binding_size: None,
                            },
                            count: None,
                        },
                    ],
                });

        let pipeline_layout =
            context
                .device
                .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                    label: Some("EQ Pipeline Layout"),
                    bind_group_layouts: &[&bind_group_layout],
                    push_constant_ranges: &[],
                });

        let pipeline = context
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("EQ Pipeline"),
                layout: Some(&pipeline_layout),
                module: &shader,
                entry_point: Some("process_eq"),
                compilation_options: Default::default(),
                cache: None,
            });

        let audio_buffer = context.create_buffer(
            (block_size * 4) as u64,
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
        );

        let coeffs_buffer = context.create_buffer(
            (num_bands * std::mem::size_of::<GpuBiquadCoeffs>()) as u64,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );

        let states_buffer = context.create_buffer(
            (num_bands * 2 * 4) as u64, // 2 states per band
            wgpu::BufferUsages::STORAGE,
        );

        let bind_group = context
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("EQ Bind Group"),
                layout: &bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: audio_buffer.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: coeffs_buffer.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: states_buffer.as_entire_binding(),
                    },
                ],
            });

        Self {
            context,
            pipeline,
            audio_buffer,
            coeffs_buffer,
            states_buffer,
            bind_group,
            num_bands,
        }
    }

    /// Update EQ coefficients
    pub fn set_coefficients(&self, coeffs: &[GpuBiquadCoeffs]) {
        self.context
            .queue
            .write_buffer(&self.coeffs_buffer, 0, bytemuck::cast_slice(coeffs));
    }

    /// Process audio through EQ
    pub fn process(&self, audio: &mut [f32]) {
        // Upload audio
        self.context
            .queue
            .write_buffer(&self.audio_buffer, 0, bytemuck::cast_slice(audio));

        // Dispatch
        let mut encoder =
            self.context
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("EQ Encoder"),
                });

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("EQ Pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);

            // One workgroup per band, process all samples
            pass.dispatch_workgroups(self.num_bands as u32, 1, 1);
        }

        self.context.queue.submit(std::iter::once(encoder.finish()));

        // Read back
        let audio_slice = self.audio_buffer.slice(0..(audio.len() * 4) as u64);
        let (tx, rx) = std::sync::mpsc::channel();

        audio_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });

        self.context.device.poll(wgpu::Maintain::Wait);
        rx.recv().unwrap().unwrap();

        let data = audio_slice.get_mapped_range();
        audio.copy_from_slice(bytemuck::cast_slice(&data));

        drop(data);
        self.audio_buffer.unmap();
    }
}

/// Async data transfer manager
pub struct AsyncTransfer {
    context: Arc<GpuContext>,
    staging_buffers: Vec<Buffer>,
    buffer_idx: usize,
}

impl AsyncTransfer {
    pub fn new(context: Arc<GpuContext>, num_buffers: usize, buffer_size: usize) -> Self {
        let staging_buffers = (0..num_buffers)
            .map(|_| {
                context.create_buffer(
                    buffer_size as u64,
                    wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
                )
            })
            .collect();

        Self {
            context,
            staging_buffers,
            buffer_idx: 0,
        }
    }

    /// Get next staging buffer (round-robin)
    pub fn next_buffer(&mut self) -> &Buffer {
        let buffer = &self.staging_buffers[self.buffer_idx];
        self.buffer_idx = (self.buffer_idx + 1) % self.staging_buffers.len();
        buffer
    }

    /// Queue async copy from GPU buffer to staging
    pub fn queue_copy(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        src: &Buffer,
        size: u64,
    ) -> usize {
        let staging = self.next_buffer();
        encoder.copy_buffer_to_buffer(src, 0, staging, 0, size);
        (self.buffer_idx + self.staging_buffers.len() - 1) % self.staging_buffers.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: GPU tests require actual GPU hardware and are typically run manually
    // These are placeholder tests that verify struct creation

    #[test]
    fn test_fft_params() {
        let params = FftParams {
            n: 1024,
            log2_n: 10,
            inverse: 0,
            _padding: 0,
        };
        assert_eq!(params.n, 1024);
        assert_eq!(params.log2_n, 10);
    }

    #[test]
    fn test_conv_params() {
        let params = ConvParams {
            ir_length: 4096,
            audio_length: 512,
            _padding: [0; 2],
        };
        assert_eq!(params.ir_length, 4096);
    }

    #[test]
    fn test_gpu_biquad_coeffs() {
        let coeffs = GpuBiquadCoeffs {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            enabled: 1,
            _padding: [0; 2],
        };
        assert_eq!(coeffs.b0, 1.0);
        assert_eq!(coeffs.enabled, 1);
    }
}
