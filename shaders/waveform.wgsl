// ReelForge Waveform Shader
// High-performance waveform rendering with:
// - Multi-level LOD (Level of Detail)
// - Min/Max/RMS display
// - Smooth anti-aliased rendering
// - Stereo visualization

struct Config {
    num_samples: u32,
    samples_per_pixel: f32,
    scroll_offset: f32,
    zoom_level: f32,
    height: f32,
    show_rms: u32,          // 0 = peak only, 1 = show RMS
    stereo_mode: u32,       // 0 = combined, 1 = split L/R
    _padding: u32,
}

// LOD data: each entry contains [min, max, rms_min, rms_max]
struct WaveformLOD {
    min_val: f32,
    max_val: f32,
    rms_min: f32,
    rms_max: f32,
}

@group(0) @binding(0) var<uniform> config: Config;
@group(0) @binding(1) var<storage, read> waveform_left: array<WaveformLOD>;
@group(0) @binding(2) var<storage, read> waveform_right: array<WaveformLOD>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

// Colors
const BG_COLOR: vec3<f32> = vec3<f32>(0.055, 0.055, 0.067);
const WAVE_COLOR_L: vec3<f32> = vec3<f32>(0.25, 0.78, 1.0);     // Cyan for left
const WAVE_COLOR_R: vec3<f32> = vec3<f32>(1.0, 0.56, 0.25);     // Orange for right
const WAVE_COLOR_MONO: vec3<f32> = vec3<f32>(0.4, 0.85, 0.6);   // Green for combined
const RMS_COLOR_L: vec3<f32> = vec3<f32>(0.15, 0.5, 0.65);      // Darker cyan
const RMS_COLOR_R: vec3<f32> = vec3<f32>(0.65, 0.35, 0.15);     // Darker orange
const RMS_COLOR_MONO: vec3<f32> = vec3<f32>(0.25, 0.55, 0.35);  // Darker green
const ZERO_LINE: vec3<f32> = vec3<f32>(0.2, 0.2, 0.25);
const CLIP_COLOR: vec3<f32> = vec3<f32>(1.0, 0.25, 0.25);       // Red for clipping

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var positions = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );

    var uvs = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.0, 0.0),
    );

    var output: VertexOutput;
    output.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    output.uv = uvs[vertex_index];
    return output;
}

// Get LOD data at position with interpolation
fn get_lod_interpolated(data: ptr<storage, array<WaveformLOD>, read>, x: f32) -> WaveformLOD {
    let sample_pos = x * f32(config.num_samples) / config.zoom_level + config.scroll_offset;
    let idx = u32(sample_pos);
    let frac = fract(sample_pos);
    let max_idx = arrayLength(data) - 1u;

    let lod0 = (*data)[min(idx, max_idx)];
    let lod1 = (*data)[min(idx + 1u, max_idx)];

    var result: WaveformLOD;
    result.min_val = mix(lod0.min_val, lod1.min_val, frac);
    result.max_val = mix(lod0.max_val, lod1.max_val, frac);
    result.rms_min = mix(lod0.rms_min, lod1.rms_min, frac);
    result.rms_max = mix(lod0.rms_max, lod1.rms_max, frac);

    return result;
}

// Check if sample is clipping
fn is_clipping(lod: WaveformLOD) -> bool {
    return abs(lod.max_val) > 0.99 || abs(lod.min_val) > 0.99;
}

// Draw waveform for a channel
fn draw_channel(
    uv: vec2<f32>,
    y_center: f32,
    y_scale: f32,
    data: ptr<storage, array<WaveformLOD>, read>,
    peak_color: vec3<f32>,
    rms_color: vec3<f32>
) -> vec3<f32> {
    let lod = get_lod_interpolated(data, uv.x);

    // Convert to screen Y coordinates
    let y_min = y_center - lod.max_val * y_scale;  // Note: inverted for screen coords
    let y_max = y_center - lod.min_val * y_scale;
    let y = uv.y;

    var color = vec3<f32>(0.0);
    var alpha = 0.0;

    // Draw RMS first (if enabled)
    if config.show_rms == 1u {
        let rms_y_min = y_center - lod.rms_max * y_scale;
        let rms_y_max = y_center - lod.rms_min * y_scale;

        if y >= rms_y_min && y <= rms_y_max {
            alpha = 0.9;
            color = rms_color;
        }
    }

    // Draw peak envelope
    if y >= y_min && y <= y_max {
        alpha = 1.0;
        color = peak_color;

        // Highlight clipping
        if is_clipping(lod) {
            color = CLIP_COLOR;
        }
    }

    // Anti-aliased edges
    let edge_width = 0.003;
    let edge_top = smoothstep(y_min - edge_width, y_min, y);
    let edge_bottom = smoothstep(y_max + edge_width, y_max, y);

    if y < y_min && y > y_min - edge_width {
        alpha = edge_top;
        color = peak_color;
    }
    if y > y_max && y < y_max + edge_width {
        alpha = 1.0 - edge_bottom;
        color = peak_color;
    }

    return color * alpha;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let uv = input.uv;
    var color = BG_COLOR;

    if config.stereo_mode == 1u {
        // Split stereo mode - top half left, bottom half right
        let y_center_l = 0.25;
        let y_center_r = 0.75;
        let y_scale = 0.2;  // Each channel takes 40% of height

        // Draw center lines
        let line_y1 = abs(uv.y - y_center_l);
        let line_y2 = abs(uv.y - y_center_r);
        let line_mid = abs(uv.y - 0.5);

        if line_y1 < 0.001 || line_y2 < 0.001 {
            color = ZERO_LINE;
        }
        if line_mid < 0.002 {
            color = ZERO_LINE * 1.5;
        }

        // Draw channels
        let left_wave = draw_channel(uv, y_center_l, y_scale, &waveform_left, WAVE_COLOR_L, RMS_COLOR_L);
        let right_wave = draw_channel(uv, y_center_r, y_scale, &waveform_right, WAVE_COLOR_R, RMS_COLOR_R);

        if length(left_wave) > 0.0 {
            color = left_wave;
        }
        if length(right_wave) > 0.0 {
            color = right_wave;
        }
    } else {
        // Combined mono mode
        let y_center = 0.5;
        let y_scale = 0.4;

        // Zero line
        let line_dist = abs(uv.y - y_center);
        if line_dist < 0.001 {
            color = ZERO_LINE;
        }

        // Combine left and right
        let lod_l = get_lod_interpolated(&waveform_left, uv.x);
        let lod_r = get_lod_interpolated(&waveform_right, uv.x);

        var combined: WaveformLOD;
        combined.min_val = min(lod_l.min_val, lod_r.min_val);
        combined.max_val = max(lod_l.max_val, lod_r.max_val);
        combined.rms_min = (lod_l.rms_min + lod_r.rms_min) * 0.5;
        combined.rms_max = (lod_l.rms_max + lod_r.rms_max) * 0.5;

        // Draw combined with a combined LOD
        let y_min = y_center - combined.max_val * y_scale;
        let y_max = y_center - combined.min_val * y_scale;
        let y = uv.y;

        // Draw RMS
        if config.show_rms == 1u {
            let rms_y_min = y_center - combined.rms_max * y_scale;
            let rms_y_max = y_center - combined.rms_min * y_scale;

            if y >= rms_y_min && y <= rms_y_max {
                color = RMS_COLOR_MONO;
            }
        }

        // Draw peak
        if y >= y_min && y <= y_max {
            color = WAVE_COLOR_MONO;
            if is_clipping(combined) {
                color = CLIP_COLOR;
            }
        }

        // Anti-aliased edges
        let edge_width = 0.003;
        if y < y_min && y > y_min - edge_width {
            let alpha = smoothstep(y_min - edge_width, y_min, y);
            color = mix(BG_COLOR, WAVE_COLOR_MONO, alpha);
        }
        if y > y_max && y < y_max + edge_width {
            let alpha = 1.0 - smoothstep(y_max, y_max + edge_width, y);
            color = mix(BG_COLOR, WAVE_COLOR_MONO, alpha);
        }
    }

    return vec4<f32>(color, 1.0);
}
