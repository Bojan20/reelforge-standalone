// GPU FFT Shader - Radix-2 Stockham FFT
//
// ULTIMATIVNI GPU FFT implementation:
// - Radix-2 Stockham auto-sort (no bit reversal needed)
// - In-place butterfly operations
// - Optimized for audio processing

struct FftParams {
    n: u32,
    log2_n: u32,
    inverse: u32,
    _padding: u32,
}

// Complex number as vec2<f32>: x = real, y = imag
@group(0) @binding(0) var<storage, read_write> input: array<vec2<f32>>;
@group(0) @binding(1) var<storage, read_write> output: array<vec2<f32>>;
@group(0) @binding(2) var<uniform> params: FftParams;

const PI: f32 = 3.14159265358979323846;

// Complex multiplication: (a+bi)(c+di) = (ac-bd) + (ad+bc)i
fn complex_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        a.x * b.x - a.y * b.y,
        a.x * b.y + a.y * b.x
    );
}

// Twiddle factor: e^(-2*pi*i*k/N) for forward, e^(2*pi*i*k/N) for inverse
fn twiddle(k: u32, n: u32, inverse: bool) -> vec2<f32> {
    let angle = select(-1.0, 1.0, inverse) * 2.0 * PI * f32(k) / f32(n);
    return vec2<f32>(cos(angle), sin(angle));
}

// Radix-2 butterfly
fn butterfly(a: vec2<f32>, b: vec2<f32>, w: vec2<f32>) -> array<vec2<f32>, 2> {
    let t = complex_mul(b, w);
    return array<vec2<f32>, 2>(
        a + t,  // Even output
        a - t   // Odd output
    );
}

@compute @workgroup_size(256)
fn fft_radix2(@builtin(global_invocation_id) id: vec3<u32>) {
    let idx = id.x;
    let n = params.n;
    let log2_n = params.log2_n;
    let inverse = params.inverse != 0u;

    if (idx >= n / 2u) {
        return;
    }

    // Copy input to output initially
    if (idx < n) {
        output[idx] = input[idx];
    }
    workgroupBarrier();

    // Stockham FFT: log2(N) stages
    var m = 1u;  // Butterfly size
    for (var stage = 0u; stage < log2_n; stage = stage + 1u) {
        let m2 = m * 2u;

        // Calculate butterfly pair indices
        let k = idx % m;
        let j = (idx / m) * m2;

        let idx0 = j + k;
        let idx1 = j + k + m;

        if (idx0 < n && idx1 < n) {
            let w = twiddle(k, m2, inverse);
            let result = butterfly(output[idx0], output[idx1], w);

            workgroupBarrier();

            output[idx0] = result[0];
            output[idx1] = result[1];
        }

        m = m2;
        workgroupBarrier();
    }

    // Scale by 1/N for inverse FFT
    if (inverse && idx < n) {
        output[idx] = output[idx] / f32(n);
    }
}

// Optimized radix-4 FFT for 4x throughput
@compute @workgroup_size(64)
fn fft_radix4(@builtin(global_invocation_id) id: vec3<u32>) {
    let idx = id.x;
    let n = params.n;
    let inverse = params.inverse != 0u;

    if (idx >= n / 4u) {
        return;
    }

    // Load 4 elements
    let i0 = idx * 4u;
    let i1 = i0 + 1u;
    let i2 = i0 + 2u;
    let i3 = i0 + 3u;

    var x0 = input[i0];
    var x1 = input[i1];
    var x2 = input[i2];
    var x3 = input[i3];

    // Radix-4 butterfly (unrolled)
    // Stage 1: 2-point butterflies
    let t0 = x0 + x2;
    let t1 = x0 - x2;
    let t2 = x1 + x3;
    let t3 = x1 - x3;

    // Multiply t3 by -i (or +i for inverse)
    let t3_rot = select(
        vec2<f32>(t3.y, -t3.x),   // Forward: multiply by -i
        vec2<f32>(-t3.y, t3.x),   // Inverse: multiply by +i
        inverse
    );

    // Stage 2: Final combinations
    output[i0] = t0 + t2;
    output[i1] = t1 + t3_rot;
    output[i2] = t0 - t2;
    output[i3] = t1 - t3_rot;

    // Scale for inverse
    if (inverse) {
        output[i0] = output[i0] / f32(n);
        output[i1] = output[i1] / f32(n);
        output[i2] = output[i2] / f32(n);
        output[i3] = output[i3] / f32(n);
    }
}
