# World-Class Audio DSP Implementations Research

## Lead DSP Engineer Analysis — Professional Audio Software Reference

---

## Table of Contents

1. [EQ Implementations](#1-eq-implementations)
   - [FabFilter Pro-Q 3/4](#fabfilter-pro-q-34)
   - [iZotope Ozone](#izotope-ozone)
   - [Sonnox Oxford EQ](#sonnox-oxford-eq)
   - [DMG Audio EQuilibrium](#dmg-audio-equilibrium)
   - [Weiss EQ1](#weiss-eq1)
   - [Massenburg DesignWorks MDWEQ](#massenburg-designworks-mdweq)
2. [Filter Topologies](#2-filter-topologies)
3. [Phase Handling Strategies](#3-phase-handling-strategies)
4. [Oversampling Implementation](#4-oversampling-implementation)
5. [SIMD Optimization](#5-simd-optimization)
6. [Dynamics Processing](#6-dynamics-processing)
7. [Metering Standards](#7-metering-standards)
8. [Spectrum Analysis](#8-spectrum-analysis)
9. [CPU Efficiency Techniques](#9-cpu-efficiency-techniques)
10. [Implementation Recommendations](#10-implementation-recommendations-for-fluxforge)

---

## 1. EQ Implementations

### FabFilter Pro-Q 3/4

**Reference:** [FabFilter Pro-Q Processing Mode](https://www.fabfilter.com/help/pro-q/using/processingmode)

#### Filter Architecture
| Feature | Specification |
|---------|---------------|
| Bands | Up to 24 |
| Filter Types | Bell, Notch, High/Low Shelf, High/Low Cut, Band Pass, Tilt Shelf, Flat Tilt |
| Slopes | 6-96 dB/oct + Brickwall |
| Internal Precision | 64-bit double |

#### Processing Modes

1. **Zero Latency Mode**
   - Minimum phase IIR implementation
   - Matches analog magnitude response precisely
   - Most CPU efficient
   - Zero samples latency

2. **Natural Phase Mode** (proprietary)
   - Matches both analog magnitude AND phase response
   - Superior to standard minimum phase at low frequencies
   - Minimal pre-ring artifacts
   - Low latency (exact value proprietary)

3. **Linear Phase Mode**
   - FIR implementation with symmetric impulse response
   - Latency options:
     - Low: 3072 samples @ 44.1kHz (~70ms)
     - Medium: 5120 samples (~116ms)
     - High: 9216 samples (~209ms)
     - Very High: 17408 samples (~395ms)
     - Maximum: Even higher for ultimate low-frequency precision

#### Dynamic EQ
- Per-band threshold, attack, release
- Intelligent auto attack/release based on program material
- Works in all phase modes including Linear Phase
- Automatic threshold detection option

#### Spectrum Analyzer
- GPU-powered graphics acceleration
- Resolution: 1024 (Low) to 8192 (Maximum) FFT points
- Tilt option: 4.5 dB/oct default for perceptually accurate display
- Range: 60/90/120 dB vertical
- Spectrum Grab feature for quick EQ adjustments

**Source:** [FabFilter Pro-Q 4](https://www.fabfilter.com/products/pro-q-4-equalizer-plug-in)

---

### iZotope Ozone

**Reference:** [Inside Ozone 12](https://www.izotope.com/en/learn/inside-ozone-12)

#### Architecture
| Feature | Specification |
|---------|---------------|
| Processing | Multiband design |
| Modules | EQ, Maximizer, Exciter, Dynamics, Imager, etc. |
| Oversampling | Global per-module |

#### DSP Highlights

1. **Maximizer IRC Modes**
   - IRC 5: Psychoacoustic model predicting audibility of distortion
   - Heavy CPU optimization for real-time performance
   - ML-based processing in newer versions

2. **Oversampling**
   - Exciter: Optional oversampling for alias reduction
   - Maximizer: Oversampling in control chain when "Prevent inter-sample clipping" enabled
   - True Peak limiting: 4x minimum oversampling

3. **Soft Clipper**
   - Steep harmonic roll-off for smooth tone
   - High-quality oversampling for aliasing prevention

**Source:** [iZotope Ozone Features](https://www.izotope.com/en/products/ozone/features)

---

### Sonnox Oxford EQ

**Reference:** [Sonnox Oxford EQ](https://sonnox.com/products/oxford-eq)

#### Heritage
Based on Sony OXF-R3 console EQ — pinnacle of digital console design from early '90s.

#### Architecture
| Feature | Specification |
|---------|---------------|
| Bands | 5 parametric + HP/LP |
| Filter Slopes | Up to 36 dB/oct |
| EQ Types | 4 distinct curve algorithms |
| Formats | AAX-DSP, Native |

#### Four EQ Types

1. **Type 1** — SSL E-style
   - Versatile, transparent
   - Everyday mixing

2. **Type 2** — Remedial
   - Asymmetric cut/boost curves
   - Excellent for resonance control
   - Best for drums/transients

3. **Type 3** — Neve/SSL G-style
   - Softer, musical curves
   - Tonal shaping on vocals/instruments

4. **Type 4** — Mastering
   - Smoothest, gentlest curves
   - Blend and balance entire mixes

**Note:** Novel coefficient generation and intelligent processing for performance surpassing analog.

**Source:** [Oxford EQ User Guide](https://dload.sonnoxplugins.com/pub/plugins/UserGuides/Oxford%20EQ%20User%20Guide.html)

---

### DMG Audio EQuilibrium

**Reference:** [DMG Audio EQuilibrium](https://dmgaudio.com/products_equilibrium.php)

#### Filter Types (Extensive)
| Category | Types |
|----------|-------|
| Classic | Coincident, Butterworth, Chebyshev, Bessel |
| Advanced | Critical, Legendre, Elliptic, Allpass |
| Vintage | Models 4000, 3, 110, 550, 88, 32, 250 |

#### Filter Slopes
- Fully parametric: 6/12/18/24/30/36/42/48 dB/oct
- First-order, second-order, vintage, tilt shelves
- Q range: 0.1 to 50
- Gain range: +/-36 dB

#### Phase Modes (Most Flexible in Industry)

1. **IIR Engine** (Low-latency tracking)
   - Digital+ Phase
   - Analogue Phase (same as EQuality)
   - ZL (Zero-Latency) Analogue Phase

2. **FIR Engine** (Mastering-grade)
   - Linear Phase
   - Analogue Phase
   - Minimum Phase
   - Zero-Latency Analogue
   - **Free Phase** — per-band phase customization

#### Advanced FIR Controls
- 12 Window Shape options
- Adjustable Impulse Length
- Per-band impulse response customization

**Source:** [DMGAudio EQuilibrium Manual](https://dmgaudio.com/dl/DMGAudio_EQuilibrium_Manual.pdf)

---

### Weiss EQ1

**Reference:** [Weiss EQ1](https://weiss.ch/products/pro-audio/eq1/)

#### Specifications
| Feature | Specification |
|---------|---------------|
| Bands | 7 identical parametric |
| Frequency | 14 Hz – 21 kHz (1/12 octave steps) |
| Q Range | 0.2 – 650 (128 steps) |
| Gain | -39 dB to +18 dB (0.1 dB steps) |
| Internal | 88.2/96 kHz, 40-bit floating-point |

#### DSP Implementation

1. **Upsampling**
   - 44.1 kHz → 88.2 kHz
   - 48 kHz → 96 kHz

2. **Filter Topology**
   - Very low noise filter architecture
   - Optimized for audio applications
   - IIR (Infinite Impulse Response)

3. **Output**
   - POW-R dithering (#1, #2, #3 algorithms)
   - Output: 16/20/24-bit

#### Plugin Version (Softube)
- True line-by-line port of original SHARC assembler code
- 64-bit double precision
- Internal oversampling
- 32-bit / 192 kHz operation

**Source:** [Weiss EQ1 - Softube](https://www.softube.com/weiss-eq1)

---

### Massenburg DesignWorks MDWEQ

**Reference:** [Massenburg MDWEQ5](https://www.uaudio.com/products/massenburg-mdweq5)

#### Historical Significance
George Massenburg invented the parametric EQ in 1971.

#### Specifications
| Feature | Specification |
|---------|---------------|
| Bands | 5 (MDWEQ5), 3 (MDWEQ3) |
| Filter Types | Shelving, Peak/Dip, Bell |
| Precision | Double-precision math |
| Character | Crystal clear, zero color, zero distortion |

#### Key Features
- Upsampling for highest resolution
- Maximum bit-depth processing
- Constant shape filter curves (GML 8200 heritage)
- IsoPeak® frequency finder
- Lowest measurable artifacts

**Source:** [MDWEQ5 FAQ](https://massenburgdesignworks.com/support/eq5-faq/)

---

## 2. Filter Topologies

### Biquad (IIR) — Transposed Direct Form II (TDF-II)

**Reference:** [Numerical Robustness of TDF-II](https://ccrma.stanford.edu/~jos/fp/Numerical_Robustness_TDF_II.html)

```
Difference Equations:
y[n] = b0 * x[n] + d1
d1   = b1 * x[n] - a1 * y[n] + d2
d2   = b2 * x[n] - a2 * y[n]
```

#### Advantages
| Benefit | Explanation |
|---------|-------------|
| Numerical Stability | Zeros precede poles, compensating attenuation |
| Floating-Point Optimal | Higher precision when operands similar magnitude |
| Sharp Transitions | Handles near pole-zero cancellations well |
| Low Memory | Only 2 state variables per biquad |

#### Best Practices
- Use 64-bit double precision for audio
- Essential at low frequencies and high sample rates
- Cascade biquads for higher-order filters
- TDF-II preferred for floating-point, DF1 for fixed-point

**Source:** [Digital Biquad Filter - Wikipedia](https://en.wikipedia.org/wiki/Digital_biquad_filter)

---

### State Variable Filter (SVF)

**Reference:** [Digital State Variable Filters - Stanford](https://ccrma.stanford.edu/~jos/svf/)

#### Chamberlin Form
- From "Musical Applications of Microprocessors" (1985)
- Simultaneous LP, HP, BP, BR outputs
- Independent frequency and Q control
- Numerically excellent at low frequencies

#### Stability Considerations
- Issues near Nyquist frequency
- Solutions:
  1. Oversampling (run filter twice)
  2. Trapezoidal integration (Andrew Simper/Cytomic ZDF)

#### ZDF (Zero-Delay Feedback) — Modern Standard
- Bilinear transform based
- Exact Q-gain relationship maintained
- Superior parameter modulation

**Source:** [Improving the Chamberlin SVF](https://www.researchgate.net/publication/356125961_Improving_the_Chamberlin_Digital_State_Variable_Filter)

---

## 3. Phase Handling Strategies

### Minimum Phase (IIR)
| Property | Value |
|----------|-------|
| Latency | Zero to very low |
| Phase Shift | Frequency-dependent |
| Pre-ringing | None |
| Best For | Tracking, mixing, real-time |

### Linear Phase (FIR)
| Property | Value |
|----------|-------|
| Latency | High (proportional to resolution) |
| Phase Shift | Zero (constant group delay) |
| Pre-ringing | Yes (symmetric impulse) |
| Best For | Mastering, parallel processing |

**Implementation:**
```
FIR Linear Phase Requirements:
- Symmetric or anti-symmetric coefficients
- Length determines low-frequency resolution
- Latency = (N-1)/2 samples
```

### Hybrid Phase (Natural Phase)
- FabFilter's proprietary approach
- Matches analog phase response
- Minimal pre-ring
- Low latency
- Exact implementation: Trade secret

**Source:** [Linear Phase EQ - FabFilter Learn](https://www.fabfilter.com/learn/equalization/linear-phase-eq)

---

## 4. Oversampling Implementation

**Reference:** [Introduction to Oversampling](https://www.nickwritesablog.com/introduction-to-oversampling-for-alias-reduction/)

### Half-Band Filter Cascade (Standard Approach)

```
8x Oversampling:
Input → 2x → 2x → 2x → Processing → 2x↓ → 2x↓ → 2x↓ → Output
```

#### Advantages
- ~50% of coefficients are zero
- Efficient polyphase implementation
- Relaxed filter specs at higher rates

### Polyphase Implementation

**Reference:** [Understanding Polyphase Filters](https://www.dsprelated.com/thread/7758/understanding-the-concept-of-polyphase-filters)

```
For Nx oversampling:
- N subfilters
- Noble Identity: Filter before upsampling = Filter after (equivalent)
- Zero-stuffed samples don't need computation
```

### Multi-Stage Design

| Stage | From | To | Filter Specs |
|-------|------|-----|--------------|
| 1 | 44.1k | 88.2k | Strongest (most taps) |
| 2 | 88.2k | 176.4k | Moderate |
| 3 | 176.4k | 352.8k | Relaxed |

### Practical Guidelines
| Application | Recommended | Notes |
|-------------|-------------|-------|
| Filter Stability | 2x | Near-Nyquist accuracy |
| Soft Saturation | 4x | Moderate harmonics |
| Hard Clipping | 8x-16x | Rich harmonics, high aliasing risk |
| EQ | 2x-4x | Depending on Q settings |

**Source:** [Anti-aliasing through oversampling - KVR](https://www.kvraudio.com/forum/viewtopic.php?t=445127)

---

## 5. SIMD Optimization

**Reference:** [KFR Library](https://github.com/kfrlib/kfr)

### Architecture Support

| Arch | Instruction Set | Vector Width | Floats/Op |
|------|-----------------|--------------|-----------|
| x86_64 | SSE4.2 | 128-bit | 4 |
| x86_64 | AVX2 | 256-bit | 8 |
| x86_64 | AVX-512 | 512-bit | 16 |
| ARM | NEON | 128-bit | 4 |
| ARM | SVE | Variable | Up to 64 |

### Biquad SIMD Strategy

**Channel Parallelism** — Most Effective Approach

```rust
// Process N channels in parallel, not N samples
// Each SIMD lane = one channel
fn process_biquad_simd_4ch(
    x: f32x4,      // 4 input samples from 4 channels
    b0: f32x4, b1: f32x4, b2: f32x4,
    a1: f32x4, a2: f32x4,
    z1: &mut f32x4, z2: &mut f32x4
) -> f32x4 {
    let y = b0 * x + *z1;
    *z1 = b1 * x - a1 * y + *z2;
    *z2 = b2 * x - a2 * y;
    y
}
```

### Optimization Results
| Technique | Speedup |
|-----------|---------|
| SIMD Biquad (channels) | ~60% |
| SIMD FIR | ~4x |
| 100x realtime | Achieved with full SIMD on mobile CPU |

### Memory Alignment
```c
// Required for optimal SIMD
__attribute__((aligned(32))) float buffer[1024];  // AVX
posix_memalign(&ptr, 32, size);                   // Dynamic
```

### Key Principles
1. **Struct of Arrays (SoA)** over Array of Structs (AoS)
2. **Channel parallelism** over sample parallelism for IIR
3. **128-bit often matches 256-bit** for IIR (data dependencies)
4. **Block processing** improves cache locality

**Source:** [Vectorizing IIR Filters](https://shafq.at/vectorizing-iir-filters.html)

---

## 6. Dynamics Processing

### Compressor/Limiter Implementation

**Reference:** [Digital Dynamic Range Compressor Design - JAES](https://www.eecs.qmul.ac.uk/~josh/documents/2012/GiannoulisMassbergReiss-dynamicrangecompression-JAES2012.pdf)

#### Detection Methods

| Method | Formula | Characteristics |
|--------|---------|-----------------|
| Peak | `|x[n]|` | Fast transients, no delay |
| RMS | `sqrt(mean(x²))` | Average level, introduces delay |
| Crest Factor | `peak / RMS` | Transient detection |

#### Envelope Follower

```
Peak Detector (1-pole):
if |x| > env:
    env = attack_coeff * env + (1 - attack_coeff) * |x|
else:
    env = release_coeff * env + (1 - release_coeff) * |x|
```

#### Gain Computer (Log Domain)

```
gain_db = threshold - (threshold - x_db) / ratio

With soft knee (width W):
if 2*(x_db - threshold) < -W:
    gain_db = x_db
elif 2*abs(x_db - threshold) <= W:
    gain_db = x_db + (1/ratio - 1) * (x_db - threshold + W/2)² / (2*W)
else:
    gain_db = threshold + (x_db - threshold) / ratio
```

#### Look-Ahead Implementation

**Reference:** [Designing a Straightforward Limiter](https://signalsmith-audio.co.uk/writing/2022/limiter/)

1. **Envelope Array** — Size = lookahead samples
2. **Forward Pass** — Build envelope from rectified input
3. **Backward Pass** — Smooth envelope ahead of peaks
4. **FIR Follower** — Converge to level within lookahead window

```
Typical lookahead: 10-30ms
Latency = lookahead time
```

### FabFilter Pro-C 2 Styles

**Reference:** [Pro-C 2 Dynamics Controls](https://www.fabfilter.com/help/pro-c/using/dynamicscontrols)

| Style | Topology | Character |
|-------|----------|-----------|
| Clean | Feedforward | Low distortion, program-dependent |
| Classic | Feedback | Vintage, very program-dependent |
| Opto | — | Slow, very soft knee, linear |
| Vocal | Auto | Automatic knee/ratio |
| Mastering | Feedforward | Transparent, catches transients |
| Bus | — | Glue for drums/mixes |
| Punch | — | Analog-like |
| Pumping | — | Deep pumping, EDM |

---

### True Peak Limiting (ITU-R BS.1770-4)

**Reference:** [ITU-R BS.1770-5](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf)

#### Algorithm Steps

1. **Attenuation** — 12.04 dB headroom (integer only)
2. **Oversampling** — 4x minimum (to 192 kHz)
3. **FIR Filter** — Half-polyphase length 12, stopband -80 dB
4. **Absolute Value** — Rectification
5. **dB Conversion** — Compensate initial attenuation

#### Implementation Notes
- Higher oversampling (8x, 16x) = more accurate
- Filter coefficients specified in ITU-R BS.1770-3 Annex 2
- Some implementations use higher ratios for precision

---

### Dynamic EQ

**Reference:** [FabFilter Pro-Q Dynamic EQ](https://www.fabfilter.com/help/pro-q/using/dynamic-eq)

#### Architecture
```
Input → Band-Limited Sidechain → Level Detector → Control Signal
                                        ↓
Input → Parametric EQ ← Gain Control ←──┘
```

#### Key Differences from Multiband Compression
| Feature | Dynamic EQ | Multiband Compressor |
|---------|------------|----------------------|
| Signal Split | Sidechain only | Full audio |
| Phase | Preserved | Crossover distortion |
| Control | Amount (dB) | Ratio |
| Transparency | Higher | Lower |

#### Per-Band Parameters
- Threshold (auto or manual)
- Attack/Release (program-dependent recommended)
- Soft knee (automatic in quality implementations)
- Band/Free triggering modes

---

## 7. Metering Standards

### LUFS/LKFS (EBU R128 / ITU-R BS.1770)

**Reference:** [EBU R128](https://tech.ebu.ch/docs/r/r128.pdf)

#### K-Weighting Filter Chain

```
Stage 1: High Shelf
- fc = 1500 Hz
- Gain = +4 dB

Stage 2: High-Pass (RLB)
- fc = 38 Hz
- Butterworth 2nd order
```

#### Measurement Windows

| Type | Window | Gating |
|------|--------|--------|
| Momentary (M) | 400 ms | None |
| Short-term (S) | 3 s | None |
| Integrated (I) | Full program | Dual-gate |

#### Dual Gating
1. **Absolute Gate:** -70 LUFS
2. **Relative Gate:** -10 LU below current integrated

#### Target Levels
| Standard | Target | Tolerance |
|----------|--------|-----------|
| EBU R128 | -23 LUFS | ±0.5 LU (±1 LU live) |
| Spotify | -14 LUFS | — |
| YouTube | -14 LUFS | — |
| Apple Music | -16 LUFS | — |

**Source:** [Loudness - EBU](https://tech.ebu.ch/loudness)

---

## 8. Spectrum Analysis

### FFT Implementation

**Reference:** [Spectrum Analysis Windows - Stanford](https://www.dsprelated.com/freebooks/sasp/Spectrum_Analysis_Windows.html)

#### Window Functions

| Window | Dynamic Range | Resolution | Use Case |
|--------|---------------|------------|----------|
| Rectangular | Lowest | Highest | Transients |
| Hann | Good | Fair | General |
| Hamming | Fair | Good | Narrowband |
| Blackman | Highest | Lowest | Wideband |
| Kaiser | Adjustable | Adjustable | Flexible |

#### Overlap Processing

```
Standard: 50-75% overlap
COLA (Constant Overlap-Add): Sum of windows = 1

Example (Hann, 50% overlap):
w[n] + w[n + N/2] = 1
```

#### FFT Sizes

| Size | Resolution @ 44.1kHz | Use Case |
|------|----------------------|----------|
| 1024 | ~43 Hz | Fast response |
| 2048 | ~21 Hz | Balanced |
| 4096 | ~11 Hz | High resolution |
| 8192 | ~5 Hz | Maximum precision |

#### Display Considerations
- Tilt: 4.5 dB/oct for perceptual accuracy
- Range: 90-120 dB typical
- Averaging: Multiple FFT frames for stability

**Source:** [Guide to FFT Analysis](https://dewesoft.com/blog/guide-to-fft-analysis)

---

## 9. CPU Efficiency Techniques

**Reference:** [Optimizing Audio DSP - CCRMA](https://ccrma.stanford.edu/events/jatin-chowdhury-optimizing-audio-dsp-modern-cpus-and-dsps-simd-caching)

### Memory Hierarchy Optimization

```
Cache Hierarchy:
L1: ~1-4 cycles
L2: ~10-20 cycles
L3: ~40-75 cycles
RAM: ~100-200 cycles
```

#### Best Practices
1. **Block Processing** — 4x4 or 8x8 tiles fit cache
2. **Linear Access** — Predictable memory patterns
3. **Recompute vs Store** — If operands in cache, recompute
4. **Stack Variables** — Quickly changing, cache-friendly

### Branch Prediction

| Type | Cost | Recommendation |
|------|------|----------------|
| Untaken | 0.5 cycles | Preferred |
| Taken | 2+ cycles | Minimize |
| Misprediction | 10-20+ cycles | Avoid |

#### Optimization Strategies
1. **Branchless Code** — Use select/blend operations
2. **Hot Path First** — Fall-through for common case
3. **Don't Inline Cold** — Keeps hot code compact
4. **Predictable Loops** — Avoid data-dependent branches

### General Guidelines

```
✓ Simple linear loops
✓ Long contiguous data blocks
✓ Predictable branches
✓ Stack-based variables
✓ SIMD-aligned data

✗ Random memory access
✗ Unpredictable branches
✗ Heavy use of std::vector in audio thread
✗ Virtual function calls in tight loops
```

**Reference:** [Agner Fog Optimization Manuals](https://www.agner.org/optimize/)

---

## 10. Implementation Recommendations for FluxForge Studio

### EQ Architecture

```rust
pub struct EqBand {
    // Coefficients
    b0: f64, b1: f64, b2: f64,
    a1: f64, a2: f64,

    // State (TDF-II)
    z1: f64, z2: f64,
}

// For 64 bands, use SIMD channel parallelism
// Process 8 bands per AVX-512 operation
pub struct Eq64Band {
    // 8 groups of 8 bands
    bands: [EqBandGroup8; 8],
}
```

### Phase Mode Implementation

| Mode | Implementation | Latency |
|------|----------------|---------|
| Zero Latency | TDF-II biquads | 0 samples |
| Natural Phase | TDF-II + phase compensation | ~64-256 samples |
| Linear Phase | FIR (partitioned convolution) | N/2 samples |

### Oversampling Strategy

```rust
pub enum OversamplingFactor {
    X1,   // No oversampling
    X2,   // Half-band filter cascade
    X4,   // 2x half-band cascade
    X8,   // 3x half-band cascade
    X16,  // 4x half-band cascade
}

// Use polyphase FIR for efficiency
// ~50% of coefficients are zero in half-band
```

### SIMD Dispatch

```rust
#[cfg(target_arch = "x86_64")]
fn process_eq_block(samples: &mut [f64], bands: &mut [EqBand]) {
    if is_x86_feature_detected!("avx512f") {
        unsafe { process_eq_avx512(samples, bands) }
    } else if is_x86_feature_detected!("avx2") {
        unsafe { process_eq_avx2(samples, bands) }
    } else if is_x86_feature_detected!("sse4.2") {
        unsafe { process_eq_sse42(samples, bands) }
    } else {
        process_eq_scalar(samples, bands)
    }
}
```

### Metering Implementation

```rust
pub struct LufsMeter {
    // K-weighting filters
    shelf_filter: BiquadTDF2,    // +4dB @ 1.5kHz
    highpass_filter: BiquadTDF2, // HPF @ 38Hz

    // Measurement windows
    momentary_buffer: RingBuffer<400ms>,
    shortterm_buffer: RingBuffer<3s>,
    integrated_sum: f64,
    integrated_count: u64,

    // Gating
    absolute_threshold: f64,     // -70 LUFS
    relative_threshold: f64,     // Updated dynamically
}

pub struct TruePeakMeter {
    // 4x oversampling FIR
    upsample_filter: PolyphaseFir,
    peak_hold: f64,
}
```

### Dynamic EQ Implementation

```rust
pub struct DynamicEqBand {
    // EQ section
    eq: EqBand,

    // Dynamics section
    threshold: f64,
    attack_coeff: f64,
    release_coeff: f64,
    max_gain_change: f64,

    // Sidechain
    sidechain_filter: EqBand,  // Band-limited
    envelope: f64,

    // Control
    auto_threshold: bool,
}
```

---

## Sources

### EQ Products
- [FabFilter Pro-Q 4](https://www.fabfilter.com/products/pro-q-4-equalizer-plug-in)
- [FabFilter Pro-Q Processing Mode](https://www.fabfilter.com/help/pro-q/using/processingmode)
- [iZotope Ozone Features](https://www.izotope.com/en/products/ozone/features)
- [Inside Ozone 12](https://www.izotope.com/en/learn/inside-ozone-12)
- [Sonnox Oxford EQ](https://sonnox.com/products/oxford-eq)
- [DMG Audio EQuilibrium](https://dmgaudio.com/products_equilibrium.php)
- [Weiss EQ1](https://weiss.ch/products/pro-audio/eq1/)
- [Weiss EQ1 - Softube](https://www.softube.com/weiss-eq1)
- [Massenburg MDWEQ5](https://www.uaudio.com/products/massenburg-mdweq5)

### Technical References
- [Digital State Variable Filters - Stanford CCRMA](https://ccrma.stanford.edu/~jos/svf/)
- [Numerical Robustness of TDF-II](https://ccrma.stanford.edu/~jos/fp/Numerical_Robustness_TDF_II.html)
- [Digital Biquad Filter - Wikipedia](https://en.wikipedia.org/wiki/Digital_biquad_filter)
- [KFR DSP Library](https://github.com/kfrlib/kfr)
- [Vectorizing IIR Filters](https://shafq.at/vectorizing-iir-filters.html)

### Standards
- [EBU R128](https://tech.ebu.ch/docs/r/r128.pdf)
- [ITU-R BS.1770-5](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf)

### Dynamics
- [Digital Dynamic Range Compressor Design - JAES](https://www.eecs.qmul.ac.uk/~josh/documents/2012/GiannoulisMassbergReiss-dynamicrangecompression-JAES2012.pdf)
- [Designing a Straightforward Limiter](https://signalsmith-audio.co.uk/writing/2022/limiter/)
- [FabFilter Pro-C 2](https://www.fabfilter.com/help/pro-c/using/dynamicscontrols)

### Optimization
- [Optimizing Audio DSP - CCRMA Talk](https://ccrma.stanford.edu/events/jatin-chowdhury-optimizing-audio-dsp-modern-cpus-and-dsps-simd-caching)
- [Introduction to Oversampling](https://www.nickwritesablog.com/introduction-to-oversampling-for-alias-reduction/)
- [Spectrum Analysis Windows](https://www.dsprelated.com/freebooks/sasp/Spectrum_Analysis_Windows.html)

---

*Document prepared for FluxForge Studio project*
*Lead DSP Engineer Analysis — January 2026*
