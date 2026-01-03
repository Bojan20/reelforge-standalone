//! Spectrum analyzer visualization

use wgpu::util::DeviceExt;

use crate::GpuContext;

/// Spectrum analyzer configuration
#[derive(Debug, Clone)]
pub struct SpectrumConfig {
    pub width: u32,
    pub height: u32,
    pub fft_size: usize,
    pub min_db: f32,
    pub max_db: f32,
    pub min_freq: f32,
    pub max_freq: f32,
    pub sample_rate: f32,
}

impl Default for SpectrumConfig {
    fn default() -> Self {
        Self {
            width: 800,
            height: 200,
            fft_size: 4096,
            min_db: -90.0,
            max_db: 0.0,
            min_freq: 20.0,
            max_freq: 20000.0,
            sample_rate: 48000.0,
        }
    }
}

/// GPU-accelerated spectrum analyzer
pub struct SpectrumAnalyzer {
    config: SpectrumConfig,
    magnitude_buffer: wgpu::Buffer,
    config_buffer: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    render_pipeline: wgpu::RenderPipeline,
}

impl SpectrumAnalyzer {
    pub fn new(ctx: &GpuContext, config: SpectrumConfig, format: wgpu::TextureFormat) -> Self {
        let bin_count = config.fft_size / 2 + 1;

        // Create magnitude buffer
        let magnitude_buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spectrum Magnitude Buffer"),
            size: (bin_count * std::mem::size_of::<f32>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Create config uniform buffer
        let config_data = SpectrumUniforms {
            min_db: config.min_db,
            max_db: config.max_db,
            min_freq: config.min_freq,
            max_freq: config.max_freq,
            sample_rate: config.sample_rate,
            fft_size: config.fft_size as u32,
            time: 0.0,
            bar_width: 1.0,
        };

        let config_buffer = ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Spectrum Config Buffer"),
                contents: bytemuck::bytes_of(&config_data),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

        // Create bind group layout
        let bind_group_layout =
            ctx.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("Spectrum Bind Group Layout"),
                    entries: &[
                        wgpu::BindGroupLayoutEntry {
                            binding: 0,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Storage { read_only: true },
                                has_dynamic_offset: false,
                                min_binding_size: None,
                            },
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 1,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Uniform,
                                has_dynamic_offset: false,
                                min_binding_size: None,
                            },
                            count: None,
                        },
                    ],
                });

        // Create bind group
        let bind_group = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Spectrum Bind Group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: magnitude_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: config_buffer.as_entire_binding(),
                },
            ],
        });

        // Create shader module
        let shader = ctx
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("Spectrum Shader"),
                source: wgpu::ShaderSource::Wgsl(SPECTRUM_SHADER.into()),
            });

        // Create pipeline layout
        let pipeline_layout = ctx
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Spectrum Pipeline Layout"),
                bind_group_layouts: &[&bind_group_layout],
                push_constant_ranges: &[],
            });

        // Create render pipeline
        let render_pipeline = ctx
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("Spectrum Render Pipeline"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs_main"),
                    buffers: &[],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::TriangleList,
                    ..Default::default()
                },
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview: None,
                cache: None,
            });

        Self {
            config,
            magnitude_buffer,
            config_buffer,
            bind_group,
            render_pipeline,
        }
    }

    /// Update magnitude data from FFT
    pub fn update_magnitudes(&self, queue: &wgpu::Queue, magnitudes: &[f32]) {
        queue.write_buffer(&self.magnitude_buffer, 0, bytemuck::cast_slice(magnitudes));
    }

    /// Render the spectrum
    pub fn render(&self, encoder: &mut wgpu::CommandEncoder, target: &wgpu::TextureView) {
        let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Spectrum Render Pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });

        render_pass.set_pipeline(&self.render_pipeline);
        render_pass.set_bind_group(0, &self.bind_group, &[]);
        render_pass.draw(0..6, 0..1); // Full-screen quad
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct SpectrumUniforms {
    min_db: f32,
    max_db: f32,
    min_freq: f32,
    max_freq: f32,
    sample_rate: f32,
    fft_size: u32,
    time: f32,
    bar_width: f32,
}

/// Pro-quality spectrum shader with peak hold, glow, and grid
const SPECTRUM_SHADER: &str = include_str!("../../../shaders/spectrum.wgsl");
