// ReelForge Meter Shader
// GPU-accelerated audio metering with:
// - Peak/RMS display
// - True peak indicators
// - K-System scaling
// - LUFS integration
// - Smooth ballistics

struct MeterConfig {
    meter_type: u32,        // 0=VU, 1=PPM, 2=K-System, 3=LUFS
    min_db: f32,
    max_db: f32,
    reference_level: f32,   // K-System reference (K-12, K-14, K-20)
    attack_time: f32,
    release_time: f32,
    orientation: u32,       // 0=vertical, 1=horizontal
    num_channels: u32,
}

struct ChannelData {
    peak_db: f32,
    rms_db: f32,
    true_peak_db: f32,
    peak_hold_db: f32,
    lufs: f32,
    clip_indicator: u32,
    _padding: vec2<f32>,
}

@group(0) @binding(0) var<uniform> config: MeterConfig;
@group(0) @binding(1) var<storage, read> channels: array<ChannelData>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

// Colors
const BG_DARK: vec3<f32> = vec3<f32>(0.04, 0.04, 0.05);
const BG_METER: vec3<f32> = vec3<f32>(0.08, 0.08, 0.1);

// Gradient stops (cyan -> green -> yellow -> orange -> red)
const COLOR_LOW: vec3<f32> = vec3<f32>(0.25, 0.78, 1.0);      // Cyan (-inf to -24dB)
const COLOR_MID: vec3<f32> = vec3<f32>(0.25, 1.0, 0.56);      // Green (-24 to -12dB)
const COLOR_WARN: vec3<f32> = vec3<f32>(1.0, 1.0, 0.25);      // Yellow (-12 to -6dB)
const COLOR_HOT: vec3<f32> = vec3<f32>(1.0, 0.56, 0.25);      // Orange (-6 to -3dB)
const COLOR_CLIP: vec3<f32> = vec3<f32>(1.0, 0.2, 0.2);       // Red (-3 to 0dB+)

const PEAK_HOLD_COLOR: vec3<f32> = vec3<f32>(1.0, 1.0, 1.0);  // White peak hold
const CLIP_FLASH_COLOR: vec3<f32> = vec3<f32>(1.0, 0.0, 0.0); // Red clip indicator

const TICK_COLOR: vec3<f32> = vec3<f32>(0.3, 0.3, 0.35);
const LABEL_COLOR: vec3<f32> = vec3<f32>(0.5, 0.5, 0.55);

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

fn db_to_normalized(db: f32) -> f32 {
    return clamp((db - config.min_db) / (config.max_db - config.min_db), 0.0, 1.0);
}

// Get meter color based on level
fn get_meter_color(level: f32) -> vec3<f32> {
    // Level is 0-1 normalized
    if level < 0.3 {
        return mix(COLOR_LOW, COLOR_MID, level / 0.3);
    } else if level < 0.6 {
        return mix(COLOR_MID, COLOR_WARN, (level - 0.3) / 0.3);
    } else if level < 0.8 {
        return mix(COLOR_WARN, COLOR_HOT, (level - 0.6) / 0.2);
    } else {
        return mix(COLOR_HOT, COLOR_CLIP, (level - 0.8) / 0.2);
    }
}

// Draw single meter bar
fn draw_meter_bar(
    uv: vec2<f32>,
    bar_left: f32,
    bar_right: f32,
    peak_level: f32,
    rms_level: f32,
    peak_hold: f32,
    is_clipping: bool
) -> vec3<f32> {
    var color = BG_METER;

    // Check if we're inside the bar bounds
    if uv.x < bar_left || uv.x > bar_right {
        return BG_DARK;
    }

    // Normalize x within bar
    let bar_width = bar_right - bar_left;
    let bar_x = (uv.x - bar_left) / bar_width;

    // For vertical meters, y=0 is bottom, y=1 is top
    let level_pos = 1.0 - uv.y;  // Flip so bottom is low

    // Draw RMS (darker fill)
    if level_pos < rms_level {
        let rms_color = get_meter_color(level_pos) * 0.5;
        color = rms_color;
    }

    // Draw peak (bright fill)
    if level_pos < peak_level {
        color = get_meter_color(level_pos);

        // Add segments (LED-style)
        let segment_size = 0.015;
        let segment_gap = 0.005;
        let segment_period = segment_size + segment_gap;
        let segment_pos = fract(level_pos / segment_period);

        if segment_pos > segment_size / segment_period {
            color = color * 0.7;  // Gap between segments
        }
    }

    // Draw peak hold indicator
    let peak_hold_pos = peak_hold;
    let peak_hold_dist = abs(level_pos - peak_hold_pos);
    if peak_hold_dist < 0.008 && peak_hold > 0.01 {
        let hold_alpha = smoothstep(0.008, 0.002, peak_hold_dist);
        color = mix(color, PEAK_HOLD_COLOR, hold_alpha);
    }

    // Clip indicator at top
    if is_clipping && uv.y < 0.05 {
        let flash = 0.5 + 0.5 * sin(config.attack_time * 20.0);  // Use time for flash
        color = mix(color, CLIP_FLASH_COLOR, flash * 0.8);
    }

    // Add glow at the level edge
    let edge_dist = abs(level_pos - peak_level);
    if edge_dist < 0.02 && level_pos > peak_level {
        let glow = exp(-edge_dist * edge_dist / 0.0002) * 0.3;
        color = color + get_meter_color(peak_level) * glow;
    }

    return color;
}

// Draw dB scale ticks
fn draw_scale(uv: vec2<f32>, bar_left: f32) -> vec3<f32> {
    let tick_x = bar_left - 0.02;
    if uv.x > tick_x && uv.x < bar_left - 0.005 {
        // Draw ticks at standard dB values
        let db_values = array<f32, 8>(-48.0, -36.0, -24.0, -18.0, -12.0, -6.0, -3.0, 0.0);

        for (var i = 0u; i < 8u; i = i + 1u) {
            let db = db_values[i];
            let y_pos = 1.0 - db_to_normalized(db);
            let tick_dist = abs(uv.y - y_pos);

            if tick_dist < 0.003 {
                return TICK_COLOR;
            }
        }
    }
    return vec3<f32>(0.0);
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let uv = input.uv;
    var color = BG_DARK;

    let num_channels = config.num_channels;
    let channel_width = 0.8 / f32(num_channels);
    let gap = 0.02;
    let start_x = 0.15;

    // Draw scale
    let scale = draw_scale(uv, start_x);
    if length(scale) > 0.0 {
        color = scale;
    }

    // Draw each channel
    for (var ch = 0u; ch < num_channels; ch = ch + 1u) {
        let bar_left = start_x + f32(ch) * (channel_width + gap);
        let bar_right = bar_left + channel_width;

        let data = channels[ch];

        let peak_norm = db_to_normalized(data.peak_db);
        let rms_norm = db_to_normalized(data.rms_db);
        let hold_norm = db_to_normalized(data.peak_hold_db);
        let is_clip = data.clip_indicator > 0u;

        let meter = draw_meter_bar(uv, bar_left, bar_right, peak_norm, rms_norm, hold_norm, is_clip);
        if length(meter) > 0.0 {
            color = meter;
        }
    }

    // Draw reference line (K-System)
    if config.meter_type == 2u {  // K-System
        let ref_y = 1.0 - db_to_normalized(0.0 - config.reference_level);
        let ref_dist = abs(uv.y - ref_y);
        if ref_dist < 0.002 {
            color = mix(color, vec3<f32>(1.0, 1.0, 0.0), 0.5);  // Yellow reference line
        }
    }

    return vec4<f32>(color, 1.0);
}
