// GPU EQ Shader - Parallel Biquad Processing
//
// ULTIMATIVNI 64-band parallel EQ:
// - One workgroup per band
// - TDF-II biquad implementation
// - Shared memory optimization

struct BiquadCoeffs {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    enabled: u32,
    _padding0: u32,
    _padding1: u32,
}

struct BiquadState {
    z1: f32,
    z2: f32,
}

@group(0) @binding(0) var<storage, read_write> audio: array<f32>;
@group(0) @binding(1) var<storage, read> coeffs: array<BiquadCoeffs>;
@group(0) @binding(2) var<storage, read_write> states: array<BiquadState>;

// Process one band across all samples
// Each workgroup handles one band
@compute @workgroup_size(1)
fn process_eq(@builtin(workgroup_id) band_id: vec3<u32>) {
    let band = band_id.x;
    let coeff = coeffs[band];

    if (coeff.enabled == 0u) {
        return;
    }

    var state = states[band];

    // Process all samples through this band's filter
    let num_samples = arrayLength(&audio);
    for (var i = 0u; i < num_samples; i = i + 1u) {
        let input = audio[i];

        // TDF-II biquad
        let output = coeff.b0 * input + state.z1;
        state.z1 = coeff.b1 * input - coeff.a1 * output + state.z2;
        state.z2 = coeff.b2 * input - coeff.a2 * output;

        audio[i] = output;
    }

    // Save state
    states[band] = state;
}

// Parallel sample processing (all bands on one sample)
// More suitable for real-time with atomic adds
@compute @workgroup_size(64)
fn process_sample_parallel(
    @builtin(local_invocation_id) band_id: vec3<u32>,
    @builtin(workgroup_id) sample_id: vec3<u32>
) {
    let band = band_id.x;
    let sample_idx = sample_id.x;
    let coeff = coeffs[band];

    if (coeff.enabled == 0u) {
        return;
    }

    // Load sample
    let input = audio[sample_idx];
    var state = states[band];

    // TDF-II biquad
    let output = coeff.b0 * input + state.z1;
    state.z1 = coeff.b1 * input - coeff.a1 * output + state.z2;
    state.z2 = coeff.b2 * input - coeff.a2 * output;

    // Save state
    states[band] = state;

    // Note: For proper band summing, we'd need atomic float adds
    // or a reduction pass. This is a simplified version.
    // In practice, bands are summed on CPU or in a separate pass.
}

// Workgroup-local shared memory for reduction
var<workgroup> band_outputs: array<f32, 64>;

// Parallel processing with reduction for summing bands
@compute @workgroup_size(64)
fn process_with_reduction(
    @builtin(local_invocation_id) local_id: vec3<u32>,
    @builtin(workgroup_id) sample_id: vec3<u32>
) {
    let band = local_id.x;
    let sample_idx = sample_id.x;
    let num_bands = 64u;

    // Initialize shared memory
    band_outputs[band] = 0.0;
    workgroupBarrier();

    if (band < num_bands) {
        let coeff = coeffs[band];

        if (coeff.enabled != 0u) {
            let input = audio[sample_idx];
            var state = states[band];

            // TDF-II biquad
            let output = coeff.b0 * input + state.z1;
            state.z1 = coeff.b1 * input - coeff.a1 * output + state.z2;
            state.z2 = coeff.b2 * input - coeff.a2 * output;

            states[band] = state;
            band_outputs[band] = output;
        }
    }

    workgroupBarrier();

    // Parallel reduction to sum all bands
    for (var stride = 32u; stride > 0u; stride = stride / 2u) {
        if (band < stride) {
            band_outputs[band] = band_outputs[band] + band_outputs[band + stride];
        }
        workgroupBarrier();
    }

    // Thread 0 writes final output
    if (band == 0u) {
        audio[sample_idx] = band_outputs[0];
    }
}
