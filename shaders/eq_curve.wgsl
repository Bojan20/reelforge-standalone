// ReelForge EQ Curve Shader
// Smooth, anti-aliased EQ curve visualization with:
// - Band response display
// - Combined curve
// - Glow effects
// - Interactive band highlighting

const MAX_BANDS: u32 = 64u;

struct Config {
    min_db: f32,
    max_db: f32,
    min_freq: f32,
    max_freq: f32,
    sample_rate: f32,
    num_bands: u32,
    highlighted_band: i32,  // -1 = none
    show_individual: u32,   // 0 = combined only, 1 = show individual
}

struct BandData {
    frequency: f32,
    gain_db: f32,
    q: f32,
    filter_type: u32,  // 0=bell, 1=lowshelf, 2=highshelf, 3=lowcut, 4=highcut, 5=notch
    enabled: u32,
    _padding: vec3<f32>,
}

@group(0) @binding(0) var<uniform> config: Config;
@group(0) @binding(1) var<storage, read> bands: array<BandData>;
@group(0) @binding(2) var<storage, read> combined_response: array<f32>;
@group(0) @binding(3) var<storage, read> band_responses: array<f32>;  // num_bands * resolution

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

// Color palette
const BG_DEEP: vec3<f32> = vec3<f32>(0.039, 0.039, 0.047);
const BG_SURFACE: vec3<f32> = vec3<f32>(0.09, 0.09, 0.11);
const GRID_COLOR: vec3<f32> = vec3<f32>(0.14, 0.14, 0.19);
const ZERO_LINE_COLOR: vec3<f32> = vec3<f32>(0.2, 0.2, 0.25);

const CURVE_COLOR_BOOST: vec3<f32> = vec3<f32>(1.0, 0.56, 0.25);   // Orange for boost
const CURVE_COLOR_CUT: vec3<f32> = vec3<f32>(0.25, 0.78, 1.0);     // Cyan for cut
const CURVE_COLOR_NEUTRAL: vec3<f32> = vec3<f32>(0.5, 0.5, 0.55);  // Gray for 0dB

const FILL_BOOST: vec3<f32> = vec3<f32>(1.0, 0.56, 0.25);
const FILL_CUT: vec3<f32> = vec3<f32>(0.25, 0.78, 1.0);

const HIGHLIGHT_COLOR: vec3<f32> = vec3<f32>(1.0, 1.0, 0.4);       // Yellow highlight
const BAND_DOT_COLOR: vec3<f32> = vec3<f32>(1.0, 1.0, 1.0);        // White band dots

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

fn log10(x: f32) -> f32 {
    return log(x) / log(10.0);
}

fn freq_to_x(freq: f32) -> f32 {
    let log_min = log10(config.min_freq);
    let log_max = log10(config.max_freq);
    return (log10(freq) - log_min) / (log_max - log_min);
}

fn x_to_freq(x: f32) -> f32 {
    let log_min = log10(config.min_freq);
    let log_max = log10(config.max_freq);
    return pow(10.0, mix(log_min, log_max, x));
}

fn db_to_y(db: f32) -> f32 {
    return 1.0 - (db - config.min_db) / (config.max_db - config.min_db);
}

fn y_to_db(y: f32) -> f32 {
    return config.min_db + (1.0 - y) * (config.max_db - config.min_db);
}

// Get response value at x position (0-1)
fn get_response_at(x: f32) -> f32 {
    let resolution = arrayLength(&combined_response);
    let idx_f = x * f32(resolution - 1u);
    let idx = u32(idx_f);
    let frac = fract(idx_f);

    let v0 = combined_response[min(idx, resolution - 1u)];
    let v1 = combined_response[min(idx + 1u, resolution - 1u)];

    return mix(v0, v1, frac);
}

// Draw frequency grid
fn draw_freq_grid(uv: vec2<f32>) -> f32 {
    let freq_lines = array<f32, 10>(20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0);

    var alpha = 0.0;
    for (var i = 0u; i < 10u; i = i + 1u) {
        let freq = freq_lines[i];
        if freq >= config.min_freq && freq <= config.max_freq {
            let x = freq_to_x(freq);
            let dist = abs(uv.x - x);
            // Major lines at 100, 1k, 10k
            let is_major = (i == 2u || i == 5u || i == 8u);
            let line_alpha = select(0.15, 0.25, is_major);
            alpha = max(alpha, smoothstep(0.002, 0.0, dist) * line_alpha);
        }
    }
    return alpha;
}

// Draw dB grid
fn draw_db_grid(uv: vec2<f32>) -> f32 {
    var alpha = 0.0;
    let db_step = 6.0;
    let num_lines = i32((config.max_db - config.min_db) / db_step);

    for (var i = 0; i <= num_lines; i = i + 1) {
        let db = config.min_db + f32(i) * db_step;
        let y = db_to_y(db);
        let dist = abs(uv.y - y);

        // Zero line is brighter
        let is_zero = abs(db) < 0.1;
        let line_alpha = select(0.15, 0.4, is_zero);
        alpha = max(alpha, smoothstep(0.002, 0.0, dist) * line_alpha);
    }
    return alpha;
}

// Signed distance to EQ curve
fn curve_distance(uv: vec2<f32>, response_db: f32) -> f32 {
    let curve_y = db_to_y(response_db);
    return uv.y - curve_y;
}

// Anti-aliased curve line
fn draw_curve_line(dist: f32, width: f32) -> f32 {
    return smoothstep(width, width * 0.3, abs(dist));
}

// Glow effect
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return intensity * exp(-dist * dist / (2.0 * radius * radius));
}

// Get curve color based on gain
fn get_curve_color(db: f32) -> vec3<f32> {
    if db > 0.5 {
        return mix(CURVE_COLOR_NEUTRAL, CURVE_COLOR_BOOST, min(db / 12.0, 1.0));
    } else if db < -0.5 {
        return mix(CURVE_COLOR_NEUTRAL, CURVE_COLOR_CUT, min(-db / 12.0, 1.0));
    }
    return CURVE_COLOR_NEUTRAL;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let uv = input.uv;

    // Background with subtle radial gradient
    let center_dist = length(uv - vec2<f32>(0.5, 0.5));
    var color = mix(BG_SURFACE, BG_DEEP, center_dist * 0.5);

    // Draw grids
    let freq_grid = draw_freq_grid(uv);
    let db_grid = draw_db_grid(uv);
    color = mix(color, GRID_COLOR, max(freq_grid, db_grid));

    // Get response at current position
    let response_db = get_response_at(uv.x);
    let dist = curve_distance(uv, response_db);
    let curve_y = db_to_y(response_db);

    // Fill area between curve and zero line
    let zero_y = db_to_y(0.0);
    if (response_db > 0.0 && uv.y > curve_y && uv.y < zero_y) ||
       (response_db < 0.0 && uv.y < curve_y && uv.y > zero_y) {
        // Fill with transparency
        let fill_color = select(FILL_CUT, FILL_BOOST, response_db > 0.0);
        let fill_alpha = 0.15 * (1.0 - abs(uv.y - curve_y) / abs(curve_y - zero_y));
        color = mix(color, fill_color, fill_alpha);
    }

    // Draw curve glow
    let glow_amount = glow(abs(dist), 0.015, 0.3);
    let curve_color = get_curve_color(response_db);
    color = color + curve_color * glow_amount;

    // Draw curve line
    let line_alpha = draw_curve_line(dist, 0.003);
    color = mix(color, curve_color, line_alpha);

    // Draw band control points
    for (var i = 0u; i < config.num_bands && i < MAX_BANDS; i = i + 1u) {
        let band = bands[i];
        if band.enabled == 1u {
            let band_x = freq_to_x(band.frequency);
            let band_y = db_to_y(band.gain_db);

            let dot_dist = length(uv - vec2<f32>(band_x, band_y));

            // Highlighted band has larger dot
            let is_highlighted = i32(i) == config.highlighted_band;
            let dot_radius = select(0.008, 0.012, is_highlighted);
            let dot_color = select(BAND_DOT_COLOR, HIGHLIGHT_COLOR, is_highlighted);

            // Outer glow
            if dot_dist < 0.03 {
                let glow_alpha = glow(dot_dist, 0.015, 0.5);
                color = color + dot_color * glow_alpha;
            }

            // Dot
            if dot_dist < dot_radius {
                let dot_alpha = smoothstep(dot_radius, dot_radius * 0.5, dot_dist);
                color = mix(color, dot_color, dot_alpha);
            }

            // Ring around highlighted band
            if is_highlighted {
                let ring_dist = abs(dot_dist - 0.02);
                let ring_alpha = smoothstep(0.003, 0.001, ring_dist) * 0.6;
                color = mix(color, HIGHLIGHT_COLOR, ring_alpha);
            }
        }
    }

    return vec4<f32>(color, 1.0);
}
