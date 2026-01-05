// GPU Filter Processing - WGSL Compute Shaders
// High-performance parallel filter processing for large audio buffers

// ============================================================================
// Common Types & Bindings
// ============================================================================

struct FilterParams {
    // Biquad coefficients
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    // Padding for alignment
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
}

struct FilterState {
    z1: f32,
    z2: f32,
    _pad0: f32,
    _pad1: f32,
}

struct ProcessConfig {
    num_samples: u32,
    num_filters: u32,
    sample_rate: f32,
    block_size: u32,
}

// Input audio buffer
@group(0) @binding(0) var<storage, read> input_buffer: array<f32>;
// Output audio buffer
@group(0) @binding(1) var<storage, read_write> output_buffer: array<f32>;
// Filter parameters (up to 64 bands)
@group(0) @binding(2) var<storage, read> filter_params: array<FilterParams, 64>;
// Filter states (per-channel, per-filter)
@group(0) @binding(3) var<storage, read_write> filter_states: array<FilterState>;
// Processing configuration
@group(0) @binding(4) var<uniform> config: ProcessConfig;

// ============================================================================
// Workgroup shared memory for efficient processing
// ============================================================================

var<workgroup> shared_samples: array<f32, 256>;
var<workgroup> shared_state: array<FilterState, 64>;

// ============================================================================
// Biquad Filter Processing (TDF-II)
// ============================================================================

fn process_biquad(input: f32, params: FilterParams, state: ptr<function, FilterState>) -> f32 {
    let output = params.b0 * input + (*state).z1;
    (*state).z1 = params.b1 * input - params.a1 * output + (*state).z2;
    (*state).z2 = params.b2 * input - params.a2 * output;
    return output;
}

@compute @workgroup_size(64)
fn biquad_filter_mono(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(local_invocation_id) local_id: vec3<u32>,
    @builtin(workgroup_id) wg_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    var sample = input_buffer[sample_idx];

    // Apply all active filters in series
    for (var i = 0u; i < config.num_filters; i++) {
        let state_idx = i;
        var state = filter_states[state_idx];
        sample = process_biquad(sample, filter_params[i], &state);
        filter_states[state_idx] = state;
    }

    output_buffer[sample_idx] = sample;
}

// ============================================================================
// Parallel Block Processing (for latency-tolerant applications)
// ============================================================================

// Process audio in parallel blocks, then combine
// Each workgroup processes a block independently

struct BlockState {
    initial_z1: f32,
    initial_z2: f32,
    final_z1: f32,
    final_z2: f32,
}

@group(1) @binding(0) var<storage, read_write> block_states: array<BlockState>;

@compute @workgroup_size(256)
fn parallel_block_filter(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(local_invocation_id) local_id: vec3<u32>,
    @builtin(workgroup_id) wg_id: vec3<u32>
) {
    let block_idx = wg_id.x;
    let sample_in_block = local_id.x;
    let global_sample = block_idx * 256u + sample_in_block;

    // Load samples to shared memory
    if global_sample < config.num_samples {
        shared_samples[sample_in_block] = input_buffer[global_sample];
    } else {
        shared_samples[sample_in_block] = 0.0;
    }

    workgroupBarrier();

    // First thread processes the entire block sequentially
    // (Required for IIR filter causality within block)
    if local_id.x == 0u {
        for (var f = 0u; f < config.num_filters; f++) {
            var state: FilterState;
            state.z1 = 0.0;
            state.z2 = 0.0;

            let params = filter_params[f];

            for (var i = 0u; i < 256u; i++) {
                if block_idx * 256u + i < config.num_samples {
                    shared_samples[i] = process_biquad(shared_samples[i], params, &state);
                }
            }

            // Store final state for block stitching
            block_states[block_idx * config.num_filters + f].final_z1 = state.z1;
            block_states[block_idx * config.num_filters + f].final_z2 = state.z2;
        }
    }

    workgroupBarrier();

    // Write output
    if global_sample < config.num_samples {
        output_buffer[global_sample] = shared_samples[sample_in_block];
    }
}

// ============================================================================
// Multi-band Processing
// ============================================================================

struct MultibandConfig {
    num_bands: u32,
    crossover_freqs: array<f32, 7>,  // Up to 8 bands
}

@group(1) @binding(1) var<uniform> multiband_config: MultibandConfig;
@group(1) @binding(2) var<storage, read_write> band_buffers: array<f32>;  // [band][sample]

// Linkwitz-Riley crossover coefficients
struct LRCrossover {
    lp_b0: f32,
    lp_b1: f32,
    lp_b2: f32,
    lp_a1: f32,
    lp_a2: f32,
    hp_b0: f32,
    hp_b1: f32,
    hp_b2: f32,
    hp_a1: f32,
    hp_a2: f32,
}

@group(1) @binding(3) var<storage, read> crossover_coeffs: array<LRCrossover, 7>;

@compute @workgroup_size(64)
fn multiband_split(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    var input_sample = input_buffer[sample_idx];
    var remaining = input_sample;

    // Split into bands using Linkwitz-Riley crossovers
    for (var band = 0u; band < multiband_config.num_bands - 1u; band++) {
        let coeffs = crossover_coeffs[band];

        // Get filter state
        let state_base = band * 4u;
        var lp_state: FilterState;
        lp_state.z1 = filter_states[state_base].z1;
        lp_state.z2 = filter_states[state_base].z2;
        var hp_state: FilterState;
        hp_state.z1 = filter_states[state_base + 1u].z1;
        hp_state.z2 = filter_states[state_base + 1u].z2;

        // Low-pass for this band
        var lp_params: FilterParams;
        lp_params.b0 = coeffs.lp_b0;
        lp_params.b1 = coeffs.lp_b1;
        lp_params.b2 = coeffs.lp_b2;
        lp_params.a1 = coeffs.lp_a1;
        lp_params.a2 = coeffs.lp_a2;

        // High-pass for remaining signal
        var hp_params: FilterParams;
        hp_params.b0 = coeffs.hp_b0;
        hp_params.b1 = coeffs.hp_b1;
        hp_params.b2 = coeffs.hp_b2;
        hp_params.a1 = coeffs.hp_a1;
        hp_params.a2 = coeffs.hp_a2;

        // Apply second order twice for LR4
        var lp_out = process_biquad(remaining, lp_params, &lp_state);
        lp_out = process_biquad(lp_out, lp_params, &lp_state);

        var hp_out = process_biquad(remaining, hp_params, &hp_state);
        hp_out = process_biquad(hp_out, hp_params, &hp_state);

        // Store band output
        band_buffers[band * config.num_samples + sample_idx] = lp_out;

        // Continue with high-pass output
        remaining = hp_out;

        // Save states
        filter_states[state_base].z1 = lp_state.z1;
        filter_states[state_base].z2 = lp_state.z2;
        filter_states[state_base + 1u].z1 = hp_state.z1;
        filter_states[state_base + 1u].z2 = hp_state.z2;
    }

    // Highest band gets remaining signal
    band_buffers[(multiband_config.num_bands - 1u) * config.num_samples + sample_idx] = remaining;
}

@compute @workgroup_size(64)
fn multiband_combine(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    var sum = 0.0;

    for (var band = 0u; band < multiband_config.num_bands; band++) {
        sum += band_buffers[band * config.num_samples + sample_idx];
    }

    output_buffer[sample_idx] = sum;
}

// ============================================================================
// Oversampling (2x, 4x, 8x)
// ============================================================================

struct OversampleConfig {
    factor: u32,        // 2, 4, or 8
    filter_taps: u32,   // Polyphase filter length
    _pad0: u32,
    _pad1: u32,
}

@group(2) @binding(0) var<uniform> oversample_config: OversampleConfig;
@group(2) @binding(1) var<storage, read> upsample_coeffs: array<f32, 256>;  // Polyphase coefficients
@group(2) @binding(2) var<storage, read> downsample_coeffs: array<f32, 256>;
@group(2) @binding(3) var<storage, read_write> oversampled_buffer: array<f32>;

@compute @workgroup_size(64)
fn upsample(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let out_idx = global_id.x;
    let factor = oversample_config.factor;

    if out_idx >= config.num_samples * factor {
        return;
    }

    let in_idx = out_idx / factor;
    let phase = out_idx % factor;

    // Polyphase upsampling
    var sum = 0.0;
    let half_taps = oversample_config.filter_taps / 2u;

    for (var i = 0u; i < oversample_config.filter_taps; i++) {
        let coeff_idx = phase * oversample_config.filter_taps + i;
        let sample_idx = in_idx + i - half_taps;

        if sample_idx < config.num_samples {
            sum += input_buffer[sample_idx] * upsample_coeffs[coeff_idx];
        }
    }

    oversampled_buffer[out_idx] = sum * f32(factor);
}

@compute @workgroup_size(64)
fn downsample(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let out_idx = global_id.x;
    let factor = oversample_config.factor;

    if out_idx >= config.num_samples {
        return;
    }

    let in_idx = out_idx * factor;

    // FIR anti-aliasing filter + decimation
    var sum = 0.0;
    let half_taps = oversample_config.filter_taps / 2u;

    for (var i = 0u; i < oversample_config.filter_taps; i++) {
        let sample_idx = in_idx + i - half_taps;

        if sample_idx < config.num_samples * factor {
            sum += oversampled_buffer[sample_idx] * downsample_coeffs[i];
        }
    }

    output_buffer[out_idx] = sum;
}

// ============================================================================
// Dynamic EQ Processing
// ============================================================================

struct DynamicEqBand {
    // Static filter params
    freq: f32,
    gain: f32,
    q: f32,
    enabled: u32,

    // Dynamic params
    threshold: f32,
    ratio: f32,
    attack_coeff: f32,
    release_coeff: f32,

    // Current envelope
    envelope: f32,
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
}

@group(3) @binding(0) var<storage, read_write> dynamic_bands: array<DynamicEqBand, 64>;
@group(3) @binding(1) var<storage, read> detector_buffer: array<f32>;  // Sidechain/detector input

@compute @workgroup_size(64)
fn dynamic_eq_detect(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let band_idx = global_id.x;

    if band_idx >= config.num_filters {
        return;
    }

    var band = dynamic_bands[band_idx];

    if band.enabled == 0u {
        return;
    }

    // Process entire block for envelope detection
    for (var i = 0u; i < config.num_samples; i++) {
        let input_level = abs(detector_buffer[i]);

        // Envelope follower
        if input_level > band.envelope {
            band.envelope = band.attack_coeff * input_level + (1.0 - band.attack_coeff) * band.envelope;
        } else {
            band.envelope = band.release_coeff * input_level + (1.0 - band.release_coeff) * band.envelope;
        }
    }

    dynamic_bands[band_idx] = band;
}

fn compute_dynamic_gain(band: DynamicEqBand) -> f32 {
    // Convert envelope to dB
    let env_db = 20.0 * log(max(band.envelope, 0.0001)) / log(10.0);

    // Above threshold: compress
    if env_db > band.threshold {
        let over = env_db - band.threshold;
        let compressed = band.threshold + over / band.ratio;
        let reduction = env_db - compressed;

        // Convert reduction to linear gain modifier
        return pow(10.0, -reduction / 20.0);
    }

    return 1.0;
}

@compute @workgroup_size(64)
fn dynamic_eq_apply(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    var sample = input_buffer[sample_idx];

    // Apply each dynamic band
    for (var i = 0u; i < config.num_filters; i++) {
        let band = dynamic_bands[i];

        if band.enabled == 0u {
            continue;
        }

        // Get dynamic gain modifier
        let dyn_gain = compute_dynamic_gain(band);

        // Modify effective gain
        let effective_gain = band.gain * dyn_gain;

        // Recalculate biquad coefficients for this gain
        // (Simplified: in practice you'd precompute multiple gain levels)
        let A = pow(10.0, effective_gain / 40.0);
        let omega = 2.0 * 3.14159265 * band.freq / config.sample_rate;
        let sin_w = sin(omega);
        let cos_w = cos(omega);
        let alpha = sin_w / (2.0 * band.q);

        let b0 = 1.0 + alpha * A;
        let b1 = -2.0 * cos_w;
        let b2 = 1.0 - alpha * A;
        let a0 = 1.0 + alpha / A;
        let a1 = -2.0 * cos_w;
        let a2 = 1.0 - alpha / A;

        var params: FilterParams;
        params.b0 = b0 / a0;
        params.b1 = b1 / a0;
        params.b2 = b2 / a0;
        params.a1 = a1 / a0;
        params.a2 = a2 / a0;

        var state = filter_states[i];
        sample = process_biquad(sample, params, &state);
        filter_states[i] = state;
    }

    output_buffer[sample_idx] = sample;
}

// ============================================================================
// FFT-based Convolution (for Linear Phase EQ)
// ============================================================================

// Note: Full FFT requires more complex implementation
// This is a simplified overlap-add convolution

struct ConvolutionConfig {
    fft_size: u32,
    ir_length: u32,
    hop_size: u32,
    num_partitions: u32,
}

@group(4) @binding(0) var<uniform> conv_config: ConvolutionConfig;
@group(4) @binding(1) var<storage, read> ir_freq: array<vec2<f32>>;  // Complex IR spectrum
@group(4) @binding(2) var<storage, read_write> input_freq: array<vec2<f32>>;  // Complex input spectrum
@group(4) @binding(3) var<storage, read_write> output_accum: array<f32>;  // Overlap-add accumulator

// Complex multiplication
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        a.x * b.x - a.y * b.y,
        a.x * b.y + a.y * b.x
    );
}

@compute @workgroup_size(64)
fn complex_multiply_add(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let bin_idx = global_id.x;

    if bin_idx >= conv_config.fft_size / 2u + 1u {
        return;
    }

    // Multiply input spectrum with IR spectrum
    let input_bin = input_freq[bin_idx];
    let ir_bin = ir_freq[bin_idx];
    let result = cmul(input_bin, ir_bin);

    // Store for IFFT (would need actual IFFT implementation)
    input_freq[bin_idx] = result;
}

// ============================================================================
// Stereo Processing
// ============================================================================

struct StereoConfig {
    width: f32,
    mid_gain: f32,
    side_gain: f32,
    pan: f32,
}

@group(5) @binding(0) var<uniform> stereo_config: StereoConfig;
@group(5) @binding(1) var<storage, read> input_left: array<f32>;
@group(5) @binding(2) var<storage, read> input_right: array<f32>;
@group(5) @binding(3) var<storage, read_write> output_left: array<f32>;
@group(5) @binding(4) var<storage, read_write> output_right: array<f32>;

@compute @workgroup_size(64)
fn stereo_process(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    let left = input_left[sample_idx];
    let right = input_right[sample_idx];

    // Convert to M/S
    let mid = (left + right) * 0.5;
    let side = (left - right) * 0.5;

    // Apply gains
    let mid_processed = mid * stereo_config.mid_gain;
    let side_processed = side * stereo_config.side_gain * stereo_config.width;

    // Convert back to L/R
    var out_left = mid_processed + side_processed;
    var out_right = mid_processed - side_processed;

    // Apply pan (constant power)
    let pan_angle = stereo_config.pan * 0.785398;  // PI/4
    let pan_left = cos(pan_angle + 0.785398);
    let pan_right = sin(pan_angle + 0.785398);

    out_left *= pan_left;
    out_right *= pan_right;

    output_left[sample_idx] = out_left;
    output_right[sample_idx] = out_right;
}

// ============================================================================
// Saturation / Waveshaping
// ============================================================================

struct SaturationConfig {
    drive: f32,
    mix: f32,
    output_gain: f32,
    mode: u32,  // 0=soft, 1=hard, 2=tube, 3=tape
}

@group(5) @binding(5) var<uniform> saturation_config: SaturationConfig;

fn soft_clip(x: f32) -> f32 {
    return x / (1.0 + abs(x));
}

fn hard_clip(x: f32) -> f32 {
    return clamp(x, -1.0, 1.0);
}

fn tube_saturate(x: f32) -> f32 {
    // Asymmetric tube-style saturation
    if x >= 0.0 {
        return 1.0 - exp(-x);
    } else {
        return -1.0 + exp(x);
    }
}

fn tape_saturate(x: f32) -> f32 {
    // Tape-style saturation with hysteresis approximation
    let k = 2.0;
    return x * (3.0 + x * x) / (1.0 + k * x * x);
}

@compute @workgroup_size(64)
fn saturate(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    let input = input_buffer[sample_idx];
    let driven = input * saturation_config.drive;

    var saturated: f32;
    switch saturation_config.mode {
        case 0u: {
            saturated = soft_clip(driven);
        }
        case 1u: {
            saturated = hard_clip(driven);
        }
        case 2u: {
            saturated = tube_saturate(driven);
        }
        case 3u: {
            saturated = tape_saturate(driven);
        }
        default: {
            saturated = soft_clip(driven);
        }
    }

    // Wet/dry mix
    let mixed = input * (1.0 - saturation_config.mix) + saturated * saturation_config.mix;

    output_buffer[sample_idx] = mixed * saturation_config.output_gain;
}

// ============================================================================
// Gain & Level Processing
// ============================================================================

struct GainConfig {
    gain_linear: f32,
    smoothing_coeff: f32,
    current_gain: f32,
    _pad: f32,
}

@group(5) @binding(6) var<storage, read_write> gain_config: GainConfig;

@compute @workgroup_size(64)
fn apply_gain_smoothed(
    @builtin(global_invocation_id) global_id: vec3<u32>
) {
    let sample_idx = global_id.x;

    if sample_idx >= config.num_samples {
        return;
    }

    // Smooth gain changes
    let target = gain_config.gain_linear;
    var current = gain_config.current_gain;

    // One-pole smoother per sample
    current = current + gain_config.smoothing_coeff * (target - current);

    output_buffer[sample_idx] = input_buffer[sample_idx] * current;

    // Update state (only last thread should write)
    if sample_idx == config.num_samples - 1u {
        gain_config.current_gain = current;
    }
}
