// GPU Convolution Shader
//
// ULTIMATIVNI convolution implementation:
// - Direct convolution for small IRs
// - Partitioned convolution support
// - Optimized memory access patterns

struct ConvParams {
    ir_length: u32,
    audio_length: u32,
    _padding0: u32,
    _padding1: u32,
}

@group(0) @binding(0) var<storage, read> audio: array<f32>;
@group(0) @binding(1) var<storage, read> ir: array<f32>;
@group(0) @binding(2) var<storage, read_write> output: array<f32>;
@group(0) @binding(3) var<uniform> params: ConvParams;

// Direct convolution - optimal for small IRs
@compute @workgroup_size(256)
fn convolve(@builtin(global_invocation_id) id: vec3<u32>) {
    let output_idx = id.x;
    let output_length = params.audio_length + params.ir_length - 1u;

    if (output_idx >= output_length) {
        return;
    }

    var sum: f32 = 0.0;

    // Convolve: y[n] = sum(x[k] * h[n-k])
    let start_k = select(0u, output_idx - params.ir_length + 1u, output_idx >= params.ir_length - 1u);
    let end_k = min(output_idx + 1u, params.audio_length);

    for (var k = start_k; k < end_k; k = k + 1u) {
        let ir_idx = output_idx - k;
        if (ir_idx < params.ir_length) {
            sum = sum + audio[k] * ir[ir_idx];
        }
    }

    output[output_idx] = sum;
}

// Frequency-domain convolution (after FFT)
@compute @workgroup_size(256)
fn convolve_spectral(@builtin(global_invocation_id) id: vec3<u32>) {
    let freq_bin = id.x;
    let fft_size = params.ir_length; // Assuming FFT size matches

    if (freq_bin >= fft_size) {
        return;
    }

    // Complex multiply: audio_spectrum * ir_spectrum
    // Input is interleaved: [real0, imag0, real1, imag1, ...]
    let idx = freq_bin * 2u;

    let audio_real = audio[idx];
    let audio_imag = audio[idx + 1u];
    let ir_real = ir[idx];
    let ir_imag = ir[idx + 1u];

    // (a+bi)(c+di) = (ac-bd) + (ad+bc)i
    output[idx] = audio_real * ir_real - audio_imag * ir_imag;
    output[idx + 1u] = audio_real * ir_imag + audio_imag * ir_real;
}

// Overlap-add accumulation
@compute @workgroup_size(256)
fn overlap_add(
    @builtin(global_invocation_id) id: vec3<u32>,
    @builtin(workgroup_id) segment_id: vec3<u32>
) {
    let sample_idx = id.x;
    let segment = segment_id.x;

    let segment_offset = segment * 256u; // Assuming block size 256
    let global_idx = segment_offset + sample_idx;

    if (global_idx >= params.audio_length + params.ir_length - 1u) {
        return;
    }

    // Accumulate overlapping segments
    // This would be called after each segment's convolution
    // output[global_idx] += current_segment_output[sample_idx];
}
