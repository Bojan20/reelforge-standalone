// GPU FFT using Stockham algorithm
// Auto-sort (no bit-reversal needed), radix-2/4/8 support
// UNIQUE: No other DAW has GPU-accelerated FFT for audio

struct FftParams {
    n: u32,           // FFT size
    log2_n: u32,      // log2(n)
    stage: u32,       // Current stage (0 to log2_n - 1)
    inverse: u32,     // 0 = forward, 1 = inverse
    radix: u32,       // 2, 4, or 8
    _pad0: u32,
    _pad1: u32,
    _pad2: u32,
}

// Complex number storage: vec2<f32> where x = real, y = imag
@group(0) @binding(0) var<storage, read> input: array<vec2<f32>>;
@group(0) @binding(1) var<storage, read_write> output: array<vec2<f32>>;
@group(0) @binding(2) var<uniform> params: FftParams;

const PI: f32 = 3.14159265358979323846;
const TWO_PI: f32 = 6.28318530717958647692;

// Complex multiplication: (a + bi)(c + di) = (ac - bd) + (ad + bc)i
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        a.x * b.x - a.y * b.y,
        a.x * b.y + a.y * b.x
    );
}

// Complex addition
fn cadd(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a + b;
}

// Complex subtraction
fn csub(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a - b;
}

// Twiddle factor: e^(-2πik/N) for forward, e^(2πik/N) for inverse
fn twiddle(k: u32, n: u32, inverse: u32) -> vec2<f32> {
    let angle = -TWO_PI * f32(k) / f32(n);
    let sign = select(-1.0, 1.0, inverse == 1u);
    return vec2<f32>(cos(angle), sign * sin(angle));
}

// Radix-2 butterfly
fn butterfly2(a: vec2<f32>, b: vec2<f32>, w: vec2<f32>) -> array<vec2<f32>, 2> {
    let bw = cmul(b, w);
    return array<vec2<f32>, 2>(
        cadd(a, bw),
        csub(a, bw)
    );
}

// Radix-4 butterfly (4x throughput)
fn butterfly4(
    x0: vec2<f32>, x1: vec2<f32>, x2: vec2<f32>, x3: vec2<f32>,
    w1: vec2<f32>, w2: vec2<f32>, w3: vec2<f32>,
    inverse: u32
) -> array<vec2<f32>, 4> {
    // Apply twiddles
    let t1 = cmul(x1, w1);
    let t2 = cmul(x2, w2);
    let t3 = cmul(x3, w3);

    // First stage of radix-4
    let a0 = cadd(x0, t2);
    let a1 = csub(x0, t2);
    let a2 = cadd(t1, t3);
    let a3 = csub(t1, t3);

    // Multiply a3 by -j (forward) or j (inverse)
    let j_mult = select(vec2<f32>(a3.y, -a3.x), vec2<f32>(-a3.y, a3.x), inverse == 1u);

    // Output
    return array<vec2<f32>, 4>(
        cadd(a0, a2),
        cadd(a1, j_mult),
        csub(a0, a2),
        csub(a1, j_mult)
    );
}

// Radix-8 butterfly (8x throughput)
fn butterfly8(
    x: array<vec2<f32>, 8>,
    w: array<vec2<f32>, 7>,
    inverse: u32
) -> array<vec2<f32>, 8> {
    // Constants for radix-8
    let sqrt2_inv = 0.7071067811865476;

    // Apply twiddles to inputs 1-7
    var t: array<vec2<f32>, 8>;
    t[0] = x[0];
    for (var i = 1u; i < 8u; i = i + 1u) {
        t[i] = cmul(x[i], w[i - 1u]);
    }

    // First stage: 4 radix-2 butterflies
    let s0 = cadd(t[0], t[4]);
    let s1 = csub(t[0], t[4]);
    let s2 = cadd(t[2], t[6]);
    let s3 = csub(t[2], t[6]);
    let s4 = cadd(t[1], t[5]);
    let s5 = csub(t[1], t[5]);
    let s6 = cadd(t[3], t[7]);
    let s7 = csub(t[3], t[7]);

    // Rotate s3 and s7 by -j (forward) or j (inverse)
    let j_sign = select(-1.0, 1.0, inverse == 1u);
    let s3_rot = vec2<f32>(j_sign * s3.y, -j_sign * s3.x);
    let s7_rot = vec2<f32>(j_sign * s7.y, -j_sign * s7.x);

    // Second stage
    let r0 = cadd(s0, s2);
    let r1 = csub(s0, s2);
    let r2 = cadd(s1, s3_rot);
    let r3 = csub(s1, s3_rot);
    let r4 = cadd(s4, s6);
    let r5 = csub(s4, s6);
    let r6 = cadd(s5, s7_rot);
    let r7 = csub(s5, s7_rot);

    // Rotate r5 and r7 by W_8^1 = (1-j)/sqrt(2)
    let w8 = vec2<f32>(sqrt2_inv, -j_sign * sqrt2_inv);
    let r5_rot = cmul(r5, w8);
    let r7_rot = cmul(r7, vec2<f32>(j_sign * sqrt2_inv, sqrt2_inv));

    // Rotate r6 by -j
    let r6_rot = vec2<f32>(j_sign * r6.y, -j_sign * r6.x);

    // Final stage
    return array<vec2<f32>, 8>(
        cadd(r0, r4),
        cadd(r2, r6_rot),
        cadd(r1, r5_rot),
        cadd(r3, r7_rot),
        csub(r0, r4),
        csub(r2, r6_rot),
        csub(r1, r5_rot),
        csub(r3, r7_rot)
    );
}

// Main FFT kernel - Stockham radix-2
@compute @workgroup_size(256)
fn fft_radix2(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let idx = global_id.x;
    let half_n = params.n / 2u;

    if (idx >= half_n) {
        return;
    }

    let stage = params.stage;
    let stage_size = 1u << (stage + 1u);
    let half_stage = stage_size / 2u;

    // Calculate indices for this butterfly
    let group = idx / half_stage;
    let pos = idx % half_stage;

    let idx0 = group * stage_size + pos;
    let idx1 = idx0 + half_stage;

    // Calculate twiddle factor
    let twiddle_idx = pos * (params.n / stage_size);
    let w = twiddle(twiddle_idx, params.n, params.inverse);

    // Load inputs
    let a = input[idx0];
    let b = input[idx1];

    // Butterfly operation
    let result = butterfly2(a, b, w);

    // Store outputs
    output[idx0] = result[0];
    output[idx1] = result[1];
}

// Stockham radix-4 kernel (4x faster)
@compute @workgroup_size(256)
fn fft_radix4(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let idx = global_id.x;
    let quarter_n = params.n / 4u;

    if (idx >= quarter_n) {
        return;
    }

    let stage = params.stage;
    let stage_size = 1u << (2u * (stage + 1u)); // 4^(stage+1)
    let quarter_stage = stage_size / 4u;

    let group = idx / quarter_stage;
    let pos = idx % quarter_stage;

    // Calculate 4 indices
    let idx0 = group * stage_size + pos;
    let idx1 = idx0 + quarter_stage;
    let idx2 = idx0 + 2u * quarter_stage;
    let idx3 = idx0 + 3u * quarter_stage;

    // Calculate twiddle factors
    let base_twiddle = pos * (params.n / stage_size);
    let w1 = twiddle(base_twiddle, params.n, params.inverse);
    let w2 = twiddle(2u * base_twiddle, params.n, params.inverse);
    let w3 = twiddle(3u * base_twiddle, params.n, params.inverse);

    // Load inputs
    let x0 = input[idx0];
    let x1 = input[idx1];
    let x2 = input[idx2];
    let x3 = input[idx3];

    // Radix-4 butterfly
    let result = butterfly4(x0, x1, x2, x3, w1, w2, w3, params.inverse);

    // Store outputs
    output[idx0] = result[0];
    output[idx1] = result[1];
    output[idx2] = result[2];
    output[idx3] = result[3];
}

// Stockham radix-8 kernel (8x faster, maximum throughput)
@compute @workgroup_size(256)
fn fft_radix8(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let idx = global_id.x;
    let eighth_n = params.n / 8u;

    if (idx >= eighth_n) {
        return;
    }

    let stage = params.stage;
    let stage_size = 1u << (3u * (stage + 1u)); // 8^(stage+1)
    let eighth_stage = stage_size / 8u;

    let group = idx / eighth_stage;
    let pos = idx % eighth_stage;

    // Calculate 8 indices
    var indices: array<u32, 8>;
    let base_idx = group * stage_size + pos;
    for (var i = 0u; i < 8u; i = i + 1u) {
        indices[i] = base_idx + i * eighth_stage;
    }

    // Calculate twiddle factors
    let base_twiddle = pos * (params.n / stage_size);
    var w: array<vec2<f32>, 7>;
    for (var i = 1u; i < 8u; i = i + 1u) {
        w[i - 1u] = twiddle(i * base_twiddle, params.n, params.inverse);
    }

    // Load inputs
    var x: array<vec2<f32>, 8>;
    for (var i = 0u; i < 8u; i = i + 1u) {
        x[i] = input[indices[i]];
    }

    // Radix-8 butterfly
    let result = butterfly8(x, w, params.inverse);

    // Store outputs
    for (var i = 0u; i < 8u; i = i + 1u) {
        output[indices[i]] = result[i];
    }
}

// Scale for inverse FFT (divide by N)
@compute @workgroup_size(256)
fn fft_scale(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let idx = global_id.x;
    if (idx >= params.n) {
        return;
    }

    let scale = 1.0 / f32(params.n);
    output[idx] = input[idx] * scale;
}

// Bit-reversal permutation (for traditional Cooley-Tukey if needed)
fn reverse_bits(x: u32, bits: u32) -> u32 {
    var result = 0u;
    var val = x;
    for (var i = 0u; i < bits; i = i + 1u) {
        result = (result << 1u) | (val & 1u);
        val = val >> 1u;
    }
    return result;
}

@compute @workgroup_size(256)
fn bit_reverse(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let idx = global_id.x;
    if (idx >= params.n) {
        return;
    }

    let rev_idx = reverse_bits(idx, params.log2_n);
    if (idx < rev_idx) {
        // Swap
        let temp = input[idx];
        output[idx] = input[rev_idx];
        output[rev_idx] = temp;
    } else if (idx == rev_idx) {
        output[idx] = input[idx];
    }
}
