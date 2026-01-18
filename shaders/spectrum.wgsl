// ReelForge Spectrum Analyzer Shader
// Pro-quality spectrum visualization with:
// - Logarithmic frequency mapping
// - Peak hold indicators
// - Smooth gradient fill
// - Glow effects
// - Grid overlay

struct Config {
    min_db: f32,
    max_db: f32,
    min_freq: f32,
    max_freq: f32,
    sample_rate: f32,
    fft_size: u32,
    time: f32,
    bar_width: f32,
    peak_hold_enabled: u32,
    _padding: u32,
}

@group(0) @binding(0) var<storage, read> magnitudes: array<f32>;
@group(0) @binding(1) var<uniform> config: Config;
@group(0) @binding(2) var<storage, read> peak_holds: array<f32>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    // Full-screen quad (2 triangles)
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

// Color palette - pro audio dark theme
const BG_DEEP: vec3<f32> = vec3<f32>(0.039, 0.039, 0.047);      // #0a0a0c
const BG_MID: vec3<f32> = vec3<f32>(0.071, 0.071, 0.086);       // #121216
const GRID_COLOR: vec3<f32> = vec3<f32>(0.14, 0.14, 0.19);      // #242430

const COLOR_LOW: vec3<f32> = vec3<f32>(0.25, 0.78, 1.0);        // Cyan
const COLOR_MID: vec3<f32> = vec3<f32>(0.25, 1.0, 0.56);        // Green
const COLOR_HIGH: vec3<f32> = vec3<f32>(1.0, 0.56, 0.25);       // Orange
const COLOR_CLIP: vec3<f32> = vec3<f32>(1.0, 0.25, 0.38);       // Red

const GLOW_COLOR: vec3<f32> = vec3<f32>(0.29, 0.62, 1.0);       // Blue glow

fn log10(x: f32) -> f32 {
    return log(x) / log(10.0);
}

fn freq_to_bin(freq: f32) -> u32 {
    return u32(freq * f32(config.fft_size) / config.sample_rate);
}

fn bin_to_freq(bin: u32) -> f32 {
    return f32(bin) * config.sample_rate / f32(config.fft_size);
}

// Catmull-Rom spline interpolation for smooth curves
fn catmull_rom(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) -> f32 {
    let t2 = t * t;
    let t3 = t2 * t;
    return 0.5 * (
        (2.0 * p1) +
        (-p0 + p2) * t +
        (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
        (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    );
}

// Get interpolated magnitude at fractional bin
fn get_magnitude_smooth(bin_f: f32) -> f32 {
    let bin = u32(bin_f);
    let frac = fract(bin_f);
    let max_bin = arrayLength(&magnitudes) - 1u;

    let p0 = magnitudes[max(bin, 1u) - 1u];
    let p1 = magnitudes[min(bin, max_bin)];
    let p2 = magnitudes[min(bin + 1u, max_bin)];
    let p3 = magnitudes[min(bin + 2u, max_bin)];

    return catmull_rom(p0, p1, p2, p3, frac);
}

// Get interpolated peak hold at fractional bin
fn get_peak_hold_smooth(bin_f: f32) -> f32 {
    let bin = u32(bin_f);
    let frac = fract(bin_f);
    let max_bin = arrayLength(&peak_holds) - 1u;

    if max_bin == 0u {
        return 0.0;
    }

    let p0 = peak_holds[max(bin, 1u) - 1u];
    let p1 = peak_holds[min(bin, max_bin)];
    let p2 = peak_holds[min(bin + 1u, max_bin)];
    let p3 = peak_holds[min(bin + 2u, max_bin)];

    return catmull_rom(p0, p1, p2, p3, frac);
}

// Get color based on frequency (bass to treble gradient)
fn get_freq_color(freq: f32, level: f32) -> vec3<f32> {
    let log_freq = log10(freq);
    let log_min = log10(config.min_freq);
    let log_max = log10(config.max_freq);
    let t = (log_freq - log_min) / (log_max - log_min);

    // Three-point gradient: cyan -> green -> orange
    var color: vec3<f32>;
    if t < 0.5 {
        color = mix(COLOR_LOW, COLOR_MID, t * 2.0);
    } else {
        color = mix(COLOR_MID, COLOR_HIGH, (t - 0.5) * 2.0);
    }

    // Add red tint near clipping
    if level > 0.9 {
        color = mix(color, COLOR_CLIP, (level - 0.9) * 10.0);
    }

    return color;
}

// Draw frequency grid lines
fn draw_grid(uv: vec2<f32>) -> f32 {
    let log_min = log10(config.min_freq);
    let log_max = log10(config.max_freq);

    // Frequency lines at: 50, 100, 200, 500, 1k, 2k, 5k, 10k, 20k
    let freq_lines = array<f32, 9>(50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0);

    var grid_alpha = 0.0;

    // Frequency grid (vertical)
    for (var i = 0u; i < 9u; i = i + 1u) {
        let freq = freq_lines[i];
        if freq >= config.min_freq && freq <= config.max_freq {
            let x = (log10(freq) - log_min) / (log_max - log_min);
            let dist = abs(uv.x - x);
            grid_alpha = max(grid_alpha, smoothstep(0.003, 0.0, dist) * 0.3);
        }
    }

    // dB grid (horizontal) - every 6dB
    let db_range = config.max_db - config.min_db;
    let db_step = 6.0;
    let num_lines = i32(db_range / db_step);

    for (var i = 0; i <= num_lines; i = i + 1) {
        let db = config.min_db + f32(i) * db_step;
        let y = (db - config.min_db) / db_range;
        let dist = abs((1.0 - uv.y) - y);
        grid_alpha = max(grid_alpha, smoothstep(0.002, 0.0, dist) * 0.2);
    }

    return grid_alpha;
}

// Soft glow effect
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return intensity * exp(-dist * dist / (2.0 * radius * radius));
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let uv = input.uv;

    // Background with subtle gradient
    var color = mix(BG_DEEP, BG_MID, uv.y * 0.5);

    // Draw grid
    let grid_alpha = draw_grid(uv);
    color = mix(color, GRID_COLOR, grid_alpha);

    // Log-frequency mapping
    let log_min = log10(config.min_freq);
    let log_max = log10(config.max_freq);
    let freq = pow(10.0, mix(log_min, log_max, uv.x));

    // Get bin with fractional interpolation
    let bin_f = freq * f32(config.fft_size) / config.sample_rate;
    let magnitude = get_magnitude_smooth(bin_f);

    // Convert to dB and normalize
    let db = 20.0 * log10(max(magnitude, 1e-10));
    let normalized = clamp((db - config.min_db) / (config.max_db - config.min_db), 0.0, 1.0);

    // Y position (0 = bottom, 1 = top)
    let y_pos = 1.0 - uv.y;

    // Draw filled spectrum with gradient
    if y_pos < normalized {
        let fill_color = get_freq_color(freq, normalized);
        // Vertical gradient - brighter at top of bar
        let brightness = 0.6 + 0.4 * (y_pos / max(normalized, 0.001));
        color = fill_color * brightness;

        // Add glow near the edge
        let edge_dist = abs(y_pos - normalized);
        let edge_glow = glow(edge_dist, 0.02, 0.5);
        color = color + GLOW_COLOR * edge_glow;
    }

    // Add subtle top edge glow on spectrum
    if y_pos < normalized + 0.03 && y_pos > normalized {
        let glow_amount = glow(y_pos - normalized, 0.015, 0.3);
        color = color + get_freq_color(freq, normalized) * glow_amount;
    }

    // Draw peak hold indicator (white line with glow)
    if config.peak_hold_enabled != 0u {
        let peak_magnitude = get_peak_hold_smooth(bin_f);
        let peak_db = 20.0 * log10(max(peak_magnitude, 1e-10));
        let peak_normalized = clamp((peak_db - config.min_db) / (config.max_db - config.min_db), 0.0, 1.0);

        // Draw thin white line at peak position
        let peak_dist = abs(y_pos - peak_normalized);
        if peak_dist < 0.004 {
            // White peak line with slight transparency
            let peak_alpha = smoothstep(0.004, 0.001, peak_dist);
            let peak_color = vec3<f32>(1.0, 1.0, 1.0);
            color = mix(color, peak_color, peak_alpha * 0.9);
        }

        // Add subtle glow below peak line
        if peak_dist < 0.02 && y_pos < peak_normalized {
            let peak_glow = glow(peak_dist, 0.01, 0.2);
            color = color + vec3<f32>(0.8, 0.8, 1.0) * peak_glow;
        }
    }

    return vec4<f32>(color, 1.0);
}
