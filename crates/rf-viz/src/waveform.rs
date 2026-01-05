//! GPU-Accelerated Waveform Renderer
//!
//! Renders audio waveforms using wgpu with:
//! - LOD (Level of Detail) for smooth zooming
//! - Min/Max/RMS display
//! - Anti-aliased lines
//! - Instanced rendering for efficiency

use crate::common::{Color, GpuContext, Viewport, VizResult};
use bytemuck::{Pod, Zeroable};
use std::sync::Arc;
use wgpu::util::DeviceExt;

/// Waveform data point (for GPU buffer)
#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct WaveformPoint {
    /// Minimum sample value (-1 to 1)
    pub min: f32,
    /// Maximum sample value (-1 to 1)
    pub max: f32,
    /// RMS value (0 to 1)
    pub rms: f32,
    /// Padding for alignment
    pub _padding: f32,
}

impl WaveformPoint {
    pub fn new(min: f32, max: f32, rms: f32) -> Self {
        Self {
            min,
            max,
            rms,
            _padding: 0.0,
        }
    }

    pub fn zero() -> Self {
        Self::new(0.0, 0.0, 0.0)
    }
}

/// Waveform uniforms for shader
#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
struct WaveformUniforms {
    viewport: Viewport,
    peak_color: Color,
    rms_color: Color,
    bg_color: Color,
    playhead_pos: f32,
    scroll_offset: f32,
    zoom: f32,
    show_rms: f32,
    sample_count: u32,
    _padding: [f32; 3],
}

/// Waveform configuration
#[derive(Clone, Debug)]
pub struct WaveformConfig {
    pub peak_color: Color,
    pub rms_color: Color,
    pub bg_color: Color,
    pub show_rms: bool,
    pub anti_alias: bool,
}

impl Default for WaveformConfig {
    fn default() -> Self {
        Self {
            peak_color: Color::BLUE,
            rms_color: Color::BLUE.with_alpha(0.6),
            bg_color: Color::new(0.04, 0.04, 0.05, 1.0),
            show_rms: true,
            anti_alias: true,
        }
    }
}

/// Pre-computed waveform data with LOD levels
pub struct WaveformData {
    /// Full resolution data
    pub full: Vec<WaveformPoint>,
    /// LOD levels (each is half the previous)
    pub lods: Vec<Vec<WaveformPoint>>,
    /// Sample rate
    pub sample_rate: f32,
    /// Duration in seconds
    pub duration: f32,
}

impl WaveformData {
    /// Create waveform data from audio samples
    pub fn from_samples(samples: &[f32], sample_rate: f32) -> Self {
        let mut data = Self {
            full: Vec::new(),
            lods: Vec::new(),
            sample_rate,
            duration: samples.len() as f32 / sample_rate,
        };

        // Generate full resolution (1 point per sample)
        data.full = samples
            .iter()
            .map(|&s| WaveformPoint::new(s, s, s.abs()))
            .collect();

        // Generate LOD levels (256, 512, 1024, 2048, 4096 samples per point)
        let current = &data.full;
        for factor in [256, 512, 1024, 2048, 4096] {
            if current.len() < factor * 2 {
                break;
            }
            let lod = Self::downsample(current, factor);
            data.lods.push(lod);
        }

        data
    }

    /// Create from stereo samples (mono mix)
    pub fn from_stereo(left: &[f32], right: &[f32], sample_rate: f32) -> Self {
        let mono: Vec<f32> = left
            .iter()
            .zip(right.iter())
            .map(|(&l, &r)| (l + r) * 0.5)
            .collect();
        Self::from_samples(&mono, sample_rate)
    }

    /// Create from min/max/rms blocks (for large files)
    pub fn from_blocks(blocks: Vec<WaveformPoint>, sample_rate: f32, samples_per_block: usize) -> Self {
        let duration = (blocks.len() * samples_per_block) as f32 / sample_rate;
        Self {
            full: blocks,
            lods: Vec::new(),
            sample_rate,
            duration,
        }
    }

    /// Downsample waveform data
    fn downsample(data: &[WaveformPoint], factor: usize) -> Vec<WaveformPoint> {
        data.chunks(factor)
            .map(|chunk| {
                let mut min = f32::MAX;
                let mut max = f32::MIN;
                let mut rms_sum = 0.0f32;

                for point in chunk {
                    min = min.min(point.min);
                    max = max.max(point.max);
                    rms_sum += point.rms * point.rms;
                }

                WaveformPoint::new(min, max, (rms_sum / chunk.len() as f32).sqrt())
            })
            .collect()
    }

    /// Get appropriate LOD for given samples per pixel
    pub fn get_lod(&self, samples_per_pixel: f32) -> &[WaveformPoint] {
        // Find LOD where each point represents roughly 1 pixel
        if samples_per_pixel <= 1.0 {
            return &self.full;
        }

        let target_factor = samples_per_pixel as usize;
        for (i, factor) in [256, 512, 1024, 2048, 4096].iter().enumerate() {
            if *factor >= target_factor && i < self.lods.len() {
                return &self.lods[i];
            }
        }

        self.lods.last().unwrap_or(&self.full)
    }
}

/// GPU Waveform Renderer
pub struct WaveformRenderer {
    ctx: Arc<GpuContext>,
    pipeline: wgpu::RenderPipeline,
    uniform_buffer: wgpu::Buffer,
    uniform_bind_group: wgpu::BindGroup,
    data_buffer: Option<wgpu::Buffer>,
    data_bind_group: Option<wgpu::BindGroup>,
    data_bind_group_layout: wgpu::BindGroupLayout,
    config: WaveformConfig,
    sample_count: u32,
}

impl WaveformRenderer {
    /// Create new waveform renderer
    pub fn new(ctx: Arc<GpuContext>, config: WaveformConfig) -> VizResult<Self> {
        let shader = ctx
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("Waveform Shader"),
                source: wgpu::ShaderSource::Wgsl(WAVEFORM_SHADER.into()),
            });

        // Uniform buffer layout
        let uniform_bind_group_layout =
            ctx.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("Waveform Uniform Layout"),
                    entries: &[wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    }],
                });

        // Data buffer layout
        let data_bind_group_layout =
            ctx.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("Waveform Data Layout"),
                    entries: &[wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::VERTEX,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Storage { read_only: true },
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    }],
                });

        let pipeline_layout = ctx
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Waveform Pipeline Layout"),
                bind_group_layouts: &[&uniform_bind_group_layout, &data_bind_group_layout],
                push_constant_ranges: &[],
            });

        let pipeline = ctx
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("Waveform Pipeline"),
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
                        format: wgpu::TextureFormat::Bgra8UnormSrgb,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::TriangleStrip,
                    ..Default::default()
                },
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview: None,
                cache: None,
            });

        // Create uniform buffer
        let uniforms = WaveformUniforms {
            viewport: Viewport::new(800.0, 100.0, 1.0),
            peak_color: config.peak_color,
            rms_color: config.rms_color,
            bg_color: config.bg_color,
            playhead_pos: 0.0,
            scroll_offset: 0.0,
            zoom: 1.0,
            show_rms: if config.show_rms { 1.0 } else { 0.0 },
            sample_count: 0,
            _padding: [0.0; 3],
        };

        let uniform_buffer = ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Waveform Uniform Buffer"),
                contents: bytemuck::cast_slice(&[uniforms]),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

        let uniform_bind_group = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Waveform Uniform Bind Group"),
            layout: &uniform_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buffer.as_entire_binding(),
            }],
        });

        Ok(Self {
            ctx,
            pipeline,
            uniform_buffer,
            uniform_bind_group,
            data_buffer: None,
            data_bind_group: None,
            data_bind_group_layout,
            config,
            sample_count: 0,
        })
    }

    /// Update waveform data
    pub fn set_data(&mut self, data: &[WaveformPoint]) {
        if data.is_empty() {
            self.data_buffer = None;
            self.data_bind_group = None;
            self.sample_count = 0;
            return;
        }

        let buffer = self
            .ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Waveform Data Buffer"),
                contents: bytemuck::cast_slice(data),
                usage: wgpu::BufferUsages::STORAGE,
            });

        let bind_group = self.ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Waveform Data Bind Group"),
            layout: &self.data_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: buffer.as_entire_binding(),
            }],
        });

        self.data_buffer = Some(buffer);
        self.data_bind_group = Some(bind_group);
        self.sample_count = data.len() as u32;
    }

    /// Update configuration
    pub fn set_config(&mut self, config: WaveformConfig) {
        self.config = config;
    }

    /// Render waveform to texture
    pub fn render(
        &mut self,
        output: &wgpu::TextureView,
        width: f32,
        height: f32,
        playhead_pos: f32,
        scroll_offset: f32,
        zoom: f32,
    ) -> VizResult<()> {
        let data_bind_group = match &self.data_bind_group {
            Some(bg) => bg,
            None => return Ok(()), // No data to render
        };

        // Update uniforms
        let uniforms = WaveformUniforms {
            viewport: Viewport::new(width, height, 1.0),
            peak_color: self.config.peak_color,
            rms_color: self.config.rms_color,
            bg_color: self.config.bg_color,
            playhead_pos,
            scroll_offset,
            zoom,
            show_rms: if self.config.show_rms { 1.0 } else { 0.0 },
            sample_count: self.sample_count,
            _padding: [0.0; 3],
        };

        self.ctx
            .queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::cast_slice(&[uniforms]));

        // Create command encoder
        let mut encoder = self
            .ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Waveform Encoder"),
            });

        // Render pass
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Waveform Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: output,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: self.config.bg_color.r as f64,
                            g: self.config.bg_color.g as f64,
                            b: self.config.bg_color.b as f64,
                            a: self.config.bg_color.a as f64,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.uniform_bind_group, &[]);
            pass.set_bind_group(1, data_bind_group, &[]);

            // Draw waveform (2 triangles per sample column = 4 vertices per column)
            // Using instancing for efficiency
            let visible_samples = (self.sample_count as f32 / zoom) as u32;
            pass.draw(0..4, 0..visible_samples);
        }

        self.ctx.queue.submit(std::iter::once(encoder.finish()));

        Ok(())
    }
}

/// WGSL shader for waveform rendering
const WAVEFORM_SHADER: &str = r#"
struct Uniforms {
    viewport: vec4<f32>,  // width, height, scale, padding
    peak_color: vec4<f32>,
    rms_color: vec4<f32>,
    bg_color: vec4<f32>,
    playhead_pos: f32,
    scroll_offset: f32,
    zoom: f32,
    show_rms: f32,
    sample_count: u32,
    padding: vec3<f32>,
}

struct WaveformPoint {
    min_val: f32,
    max_val: f32,
    rms: f32,
    padding: f32,
}

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(1) @binding(0) var<storage, read> data: array<WaveformPoint>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) is_rms: f32,
}

@vertex
fn vs_main(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
) -> VertexOutput {
    var out: VertexOutput;

    let width = u.viewport.x;
    let height = u.viewport.y;
    let sample_count = f32(u.sample_count);

    // Calculate which sample this instance represents
    let visible_samples = sample_count / u.zoom;
    let start_sample = u.scroll_offset * sample_count;
    let sample_idx = u32(start_sample + f32(instance_index));

    // Bounds check
    if sample_idx >= u.sample_count {
        out.position = vec4<f32>(2.0, 2.0, 0.0, 1.0); // Off screen
        return out;
    }

    let point = data[sample_idx];

    // X position (column for this sample)
    let x_norm = f32(instance_index) / visible_samples;
    let x = x_norm * 2.0 - 1.0;
    let col_width = 2.0 / visible_samples;

    // Y positions
    let center_y = 0.0;
    let scale = 0.9; // Leave some margin

    // Determine if this is peak or RMS quad
    let quad_type = vertex_index / 4u; // 0 = peak, 1 = RMS
    let local_vertex = vertex_index % 4u;

    var y_top: f32;
    var y_bottom: f32;

    if quad_type == 0u {
        // Peak envelope
        y_top = center_y + point.max_val * scale;
        y_bottom = center_y + point.min_val * scale;
        out.is_rms = 0.0;
    } else {
        // RMS envelope
        y_top = center_y + point.rms * scale;
        y_bottom = center_y - point.rms * scale;
        out.is_rms = 1.0;
    }

    // Generate quad vertices (triangle strip: 0-1-2-3)
    var pos: vec2<f32>;
    switch local_vertex {
        case 0u: { pos = vec2<f32>(x, y_top); }
        case 1u: { pos = vec2<f32>(x + col_width, y_top); }
        case 2u: { pos = vec2<f32>(x, y_bottom); }
        case 3u: { pos = vec2<f32>(x + col_width, y_bottom); }
        default: { pos = vec2<f32>(0.0, 0.0); }
    }

    out.position = vec4<f32>(pos, 0.0, 1.0);
    out.uv = (pos + 1.0) * 0.5;

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    if in.is_rms > 0.5 && u.show_rms < 0.5 {
        discard;
    }

    let color = select(u.peak_color, u.rms_color, in.is_rms > 0.5);

    // Apply subtle gradient based on Y position
    let gradient = 1.0 - abs(in.uv.y - 0.5) * 0.3;

    return vec4<f32>(color.rgb * gradient, color.a);
}
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_waveform_data_from_samples() {
        let samples: Vec<f32> = (0..4800)
            .map(|i| (i as f32 * 0.1).sin())
            .collect();

        let data = WaveformData::from_samples(&samples, 48000.0);

        assert_eq!(data.full.len(), 4800);
        assert!(data.duration > 0.0);
    }

    #[test]
    fn test_waveform_point() {
        let point = WaveformPoint::new(-0.5, 0.8, 0.3);
        assert_eq!(point.min, -0.5);
        assert_eq!(point.max, 0.8);
        assert_eq!(point.rms, 0.3);
    }

    #[test]
    fn test_waveform_lod() {
        let samples: Vec<f32> = (0..48000)
            .map(|i| (i as f32 * 0.01).sin())
            .collect();

        let data = WaveformData::from_samples(&samples, 48000.0);

        // At high zoom (few samples per pixel), use full resolution
        let lod1 = data.get_lod(0.5);
        assert_eq!(lod1.len(), data.full.len());

        // At low zoom, use LOD
        let lod2 = data.get_lod(500.0);
        assert!(lod2.len() < data.full.len());
    }
}
