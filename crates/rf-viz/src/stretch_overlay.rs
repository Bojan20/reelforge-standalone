//! # Time Stretch Visualization
//!
//! GPU-accelerated rendering for time stretch regions and flex markers on timeline.
//!
//! ## Features
//!
//! - Color-coded stretch regions (cyan=compress, orange=expand)
//! - Flex marker rendering with handles
//! - Transient marker display
//! - Stretch ratio indicators

use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::common::{GpuContext, VizResult};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Stretch region for visualization
#[derive(Debug, Clone, Copy)]
pub struct StretchRegionViz {
    /// Start X position (normalized 0.0 - 1.0)
    pub start_x: f32,
    /// End X position (normalized 0.0 - 1.0)
    pub end_x: f32,
    /// Stretch ratio (1.0 = no stretch)
    pub ratio: f32,
}

/// Flex marker type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MarkerType {
    /// Auto-detected transient
    Transient,
    /// User-placed warp marker
    WarpMarker,
    /// Beat grid marker
    BeatMarker,
    /// Anchor point
    Anchor,
}

/// Flex marker for visualization
#[derive(Debug, Clone, Copy)]
pub struct FlexMarkerViz {
    /// X position (normalized 0.0 - 1.0)
    pub x: f32,
    /// Marker type
    pub marker_type: MarkerType,
    /// Confidence (0.0 - 1.0)
    pub confidence: f32,
    /// Is selected
    pub selected: bool,
}

// ═══════════════════════════════════════════════════════════════════════════════
// GPU TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Vertex for stretch region overlay
#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct StretchVertex {
    pub position: [f32; 2],
    pub color: [f32; 4],
}

/// Uniform buffer for view transformation
#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct ViewUniforms {
    /// View offset X
    pub offset_x: f32,
    /// View scale X
    pub scale_x: f32,
    /// View height
    pub height: f32,
    /// Padding
    pub _pad: f32,
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRETCH OVERLAY RENDERER
// ═══════════════════════════════════════════════════════════════════════════════

/// GPU renderer for stretch overlays
pub struct StretchOverlayRenderer {
    /// GPU context reference
    context: GpuContext,
    /// Region render pipeline
    region_pipeline: wgpu::RenderPipeline,
    /// Marker render pipeline
    marker_pipeline: wgpu::RenderPipeline,
    /// Vertex buffer for regions
    region_vertex_buffer: wgpu::Buffer,
    /// Vertex buffer for markers
    marker_vertex_buffer: wgpu::Buffer,
    /// Uniform buffer
    uniform_buffer: wgpu::Buffer,
    /// Bind group
    bind_group: wgpu::BindGroup,
    /// Maximum regions
    max_regions: usize,
    /// Maximum markers
    max_markers: usize,
    /// Current region count
    region_count: usize,
    /// Current marker count
    marker_count: usize,
}

impl StretchOverlayRenderer {
    /// Create new renderer
    pub fn new(context: GpuContext) -> VizResult<Self> {
        let device = &context.device;

        // Create shader modules
        let region_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Stretch Region Shader"),
            source: wgpu::ShaderSource::Wgsl(REGION_SHADER.into()),
        });

        let marker_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Flex Marker Shader"),
            source: wgpu::ShaderSource::Wgsl(MARKER_SHADER.into()),
        });

        // Create uniform buffer
        let uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Stretch Uniform Buffer"),
            contents: bytemuck::cast_slice(&[ViewUniforms {
                offset_x: 0.0,
                scale_x: 1.0,
                height: 1.0,
                _pad: 0.0,
            }]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        // Create bind group layout
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Stretch Bind Group Layout"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::VERTEX,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });

        // Create bind group
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Stretch Bind Group"),
            layout: &bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buffer.as_entire_binding(),
            }],
        });

        // Create pipeline layout
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Stretch Pipeline Layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        // Create region pipeline
        let region_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Stretch Region Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &region_shader,
                entry_point: Some("vs_main"),
                buffers: &[wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<StretchVertex>() as wgpu::BufferAddress,
                    step_mode: wgpu::VertexStepMode::Vertex,
                    attributes: &[
                        wgpu::VertexAttribute {
                            offset: 0,
                            shader_location: 0,
                            format: wgpu::VertexFormat::Float32x2,
                        },
                        wgpu::VertexAttribute {
                            offset: 8,
                            shader_location: 1,
                            format: wgpu::VertexFormat::Float32x4,
                        },
                    ],
                }],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &region_shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: wgpu::TextureFormat::Bgra8UnormSrgb,
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

        // Create marker pipeline
        let marker_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Flex Marker Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &marker_shader,
                entry_point: Some("vs_main"),
                buffers: &[wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<StretchVertex>() as wgpu::BufferAddress,
                    step_mode: wgpu::VertexStepMode::Vertex,
                    attributes: &[
                        wgpu::VertexAttribute {
                            offset: 0,
                            shader_location: 0,
                            format: wgpu::VertexFormat::Float32x2,
                        },
                        wgpu::VertexAttribute {
                            offset: 8,
                            shader_location: 1,
                            format: wgpu::VertexFormat::Float32x4,
                        },
                    ],
                }],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &marker_shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: wgpu::TextureFormat::Bgra8UnormSrgb,
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

        // Create vertex buffers
        let max_regions = 1024;
        let max_markers = 4096;

        let region_vertex_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Stretch Region Vertex Buffer"),
            size: (max_regions * 6 * std::mem::size_of::<StretchVertex>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let marker_vertex_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Flex Marker Vertex Buffer"),
            size: (max_markers * 6 * std::mem::size_of::<StretchVertex>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        Ok(Self {
            context,
            region_pipeline,
            marker_pipeline,
            region_vertex_buffer,
            marker_vertex_buffer,
            uniform_buffer,
            bind_group,
            max_regions,
            max_markers,
            region_count: 0,
            marker_count: 0,
        })
    }

    /// Update stretch regions
    pub fn update_regions(&mut self, regions: &[StretchRegionViz]) {
        let mut vertices = Vec::with_capacity(regions.len() * 6);

        for region in regions.iter().take(self.max_regions) {
            let color = region_color(region.ratio);

            // Create quad (two triangles)
            // Triangle 1
            vertices.push(StretchVertex { position: [region.start_x, 0.0], color });
            vertices.push(StretchVertex { position: [region.end_x, 0.0], color });
            vertices.push(StretchVertex { position: [region.end_x, 1.0], color });
            // Triangle 2
            vertices.push(StretchVertex { position: [region.start_x, 0.0], color });
            vertices.push(StretchVertex { position: [region.end_x, 1.0], color });
            vertices.push(StretchVertex { position: [region.start_x, 1.0], color });
        }

        self.region_count = vertices.len() / 6;

        if !vertices.is_empty() {
            self.context.queue.write_buffer(
                &self.region_vertex_buffer,
                0,
                bytemuck::cast_slice(&vertices),
            );
        }
    }

    /// Update flex markers
    pub fn update_markers(&mut self, markers: &[FlexMarkerViz]) {
        let mut vertices = Vec::with_capacity(markers.len() * 6);

        for marker in markers.iter().take(self.max_markers) {
            let color = marker_color(marker.marker_type, marker.selected, marker.confidence);
            let width = marker_width(marker.marker_type, marker.selected);

            // Create thin vertical line as quad
            let x0 = marker.x - width / 2.0;
            let x1 = marker.x + width / 2.0;

            // Triangle 1
            vertices.push(StretchVertex { position: [x0, 0.0], color });
            vertices.push(StretchVertex { position: [x1, 0.0], color });
            vertices.push(StretchVertex { position: [x1, 1.0], color });
            // Triangle 2
            vertices.push(StretchVertex { position: [x0, 0.0], color });
            vertices.push(StretchVertex { position: [x1, 1.0], color });
            vertices.push(StretchVertex { position: [x0, 1.0], color });
        }

        self.marker_count = vertices.len() / 6;

        if !vertices.is_empty() {
            self.context.queue.write_buffer(
                &self.marker_vertex_buffer,
                0,
                bytemuck::cast_slice(&vertices),
            );
        }
    }

    /// Update view uniforms
    pub fn update_view(&mut self, offset_x: f32, scale_x: f32, height: f32) {
        let uniforms = ViewUniforms {
            offset_x,
            scale_x,
            height,
            _pad: 0.0,
        };

        self.context.queue.write_buffer(
            &self.uniform_buffer,
            0,
            bytemuck::cast_slice(&[uniforms]),
        );
    }

    /// Render stretch overlay
    pub fn render(&self, encoder: &mut wgpu::CommandEncoder, view: &wgpu::TextureView) {
        let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Stretch Overlay Pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load, // Don't clear - overlay on existing content
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });

        // Render regions
        if self.region_count > 0 {
            render_pass.set_pipeline(&self.region_pipeline);
            render_pass.set_bind_group(0, &self.bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.region_vertex_buffer.slice(..));
            render_pass.draw(0..(self.region_count * 6) as u32, 0..1);
        }

        // Render markers
        if self.marker_count > 0 {
            render_pass.set_pipeline(&self.marker_pipeline);
            render_pass.set_bind_group(0, &self.bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.marker_vertex_buffer.slice(..));
            render_pass.draw(0..(self.marker_count * 6) as u32, 0..1);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get color for stretch region based on ratio
fn region_color(ratio: f32) -> [f32; 4] {
    if ratio < 0.99 {
        // Compression - cyan/teal
        let intensity = (1.0 - ratio).min(1.0);
        [0.0, 0.5 + intensity * 0.3, 0.7 + intensity * 0.2, 0.2 + intensity * 0.1]
    } else if ratio > 1.01 {
        // Expansion - orange/red
        let intensity = ((ratio - 1.0) * 2.0).min(1.0);
        [0.9, 0.4 - intensity * 0.2, 0.0, 0.2 + intensity * 0.1]
    } else {
        // No stretch - transparent
        [0.0, 0.0, 0.0, 0.0]
    }
}

/// Get color for marker based on type
fn marker_color(marker_type: MarkerType, selected: bool, confidence: f32) -> [f32; 4] {
    let alpha = if selected { 1.0 } else { 0.4 + confidence * 0.4 };

    match marker_type {
        MarkerType::Transient => [0.6, 0.6, 0.6, alpha], // Gray
        MarkerType::WarpMarker => {
            if selected {
                [1.0, 0.6, 0.0, alpha] // Bright orange
            } else {
                [0.9, 0.5, 0.1, alpha] // Orange
            }
        }
        MarkerType::BeatMarker => [0.3, 0.5, 0.9, alpha], // Blue
        MarkerType::Anchor => [0.9, 0.2, 0.2, alpha],     // Red
    }
}

/// Get marker line width
fn marker_width(marker_type: MarkerType, selected: bool) -> f32 {
    let base = match marker_type {
        MarkerType::Transient => 0.001,
        MarkerType::WarpMarker => 0.002,
        MarkerType::BeatMarker => 0.001,
        MarkerType::Anchor => 0.003,
    };

    if selected { base * 2.0 } else { base }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHADERS
// ═══════════════════════════════════════════════════════════════════════════════

const REGION_SHADER: &str = r#"
struct ViewUniforms {
    offset_x: f32,
    scale_x: f32,
    height: f32,
    _pad: f32,
}

@group(0) @binding(0) var<uniform> view: ViewUniforms;

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    // Transform position
    let x = (in.position.x - view.offset_x) * view.scale_x * 2.0 - 1.0;
    let y = in.position.y * 2.0 - 1.0;

    out.clip_position = vec4<f32>(x, y, 0.0, 1.0);
    out.color = in.color;

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}
"#;

const MARKER_SHADER: &str = r#"
struct ViewUniforms {
    offset_x: f32,
    scale_x: f32,
    height: f32,
    _pad: f32,
}

@group(0) @binding(0) var<uniform> view: ViewUniforms;

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    // Transform position
    let x = (in.position.x - view.offset_x) * view.scale_x * 2.0 - 1.0;
    let y = in.position.y * 2.0 - 1.0;

    out.clip_position = vec4<f32>(x, y, 0.0, 1.0);
    out.color = in.color;

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_region_color_compression() {
        let color = region_color(0.5);
        // Should be cyan-ish
        assert!(color[1] > color[0]); // More green than red
        assert!(color[2] > 0.0);      // Some blue
        assert!(color[3] > 0.0);      // Some alpha
    }

    #[test]
    fn test_region_color_expansion() {
        let color = region_color(2.0);
        // Should be orange-ish
        assert!(color[0] > color[1]); // More red than green
        assert!(color[3] > 0.0);      // Some alpha
    }

    #[test]
    fn test_region_color_unity() {
        let color = region_color(1.0);
        // Should be transparent
        assert!(color[3] < 0.01);
    }

    #[test]
    fn test_marker_color() {
        let transient = marker_color(MarkerType::Transient, false, 1.0);
        let warp = marker_color(MarkerType::WarpMarker, false, 1.0);

        // Transient should be gray (r ≈ g ≈ b)
        assert!((transient[0] - transient[1]).abs() < 0.1);

        // Warp should be orange (r > g > b)
        assert!(warp[0] > warp[1]);
        assert!(warp[1] > warp[2]);
    }
}
