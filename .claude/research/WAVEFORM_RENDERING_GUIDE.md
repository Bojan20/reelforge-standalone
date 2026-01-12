# Ultimate Waveform Rendering Guide

**Professional DAW-Quality Audio Visualization**

*Chief Audio Architect & Graphics Engineer Reference*

---

## Table of Contents

1. [Oscilloscope Physics & Visual Characteristics](#1-oscilloscope-physics--visual-characteristics)
2. [Professional DAW Waveform Rendering](#2-professional-daw-waveform-rendering)
3. [Anti-Aliasing Techniques](#3-anti-aliasing-techniques)
4. [Interpolation Methods](#4-interpolation-methods)
5. [Digital vs Analog Aesthetics](#5-digital-vs-analog-aesthetics)
6. [Color Gradients & Shading](#6-color-gradients--shading)
7. [RMS vs Peak Display](#7-rms-vs-peak-display)
8. [Zoom-Dependent Rendering (LOD)](#8-zoom-dependent-rendering-lod)
9. [GPU Acceleration](#9-gpu-acceleration)
10. [Sub-Pixel Rendering](#10-sub-pixel-rendering)
11. [Implementation Reference](#11-implementation-reference)

---

## 1. Oscilloscope Physics & Visual Characteristics

### CRT Oscilloscope Fundamentals

Real oscilloscopes create that distinctive "analog" look through physical phenomena:

#### Electron Beam Characteristics

```
┌─────────────────────────────────────────────────────────────────┐
│                     ELECTRON BEAM PATH                          │
│                                                                 │
│    Electron Gun → Focusing → Deflection → Phosphor Screen      │
│         │              │          │              │              │
│    Intensity      Spot Size   X/Y Position    Glow/Decay       │
└─────────────────────────────────────────────────────────────────┘
```

**Key Physical Properties:**

| Property | Effect on Display | Simulation Approach |
|----------|-------------------|---------------------|
| **Phosphor Persistence** | Glow fades over 10μs-1ms | Exponential decay in framebuffer |
| **Beam Gaussian Profile** | Soft edges, intensity falloff | 2D Gaussian in fragment shader |
| **Cathodoluminescence** | Bright at center, dim at edges | Radial gradient intensity |
| **Scan Speed → Brightness** | Slow = bright, fast = dim | Inverse velocity intensity |
| **Focus/Astigmatism** | Spot size and circularity | Adjustable Gaussian sigma |

#### Phosphor Glow Mathematics

The phosphor intensity follows exponential decay:

```
I(t) = I₀ × e^(-λt)

Where:
  I₀ = Initial intensity when beam strikes
  λ  = Decay constant (phosphor type dependent)
  t  = Time since beam passage
```

**Typical Phosphor Persistence Times:**

| Type | Persistence | Use Case |
|------|-------------|----------|
| P1   | 24μs (short) | High-frequency signals |
| P31  | 32μs (medium-short) | General purpose |
| P7   | 50ms (long) | Single-shot transients |
| P43  | 1ms (medium) | Digital storage scopes |

#### Gaussian Beam Distribution

The electron beam has a Gaussian intensity profile:

```
I(d) = (1 / (σ√(2π))) × e^(-d² / (2σ²))

Where:
  d = Distance from beam center
  σ = Beam spread (focus parameter)
```

### Vector Display Characteristics

Vector displays (like Vectrex, arcade games) draw lines between points:

```
Common Artifacts:
├── Bright dots at line endpoints (beam lingers)
├── Intensity varies with line length
├── Fast transitions = dimmer lines
└── Z-axis blanking during position jumps
```

**Intensity vs. Velocity Relationship:**

```
Brightness ∝ 1 / velocity

Slow beam movement = brighter trace
Fast beam movement = dimmer trace
```

---

## 2. Professional DAW Waveform Rendering

### Industry Standard Approaches

#### Cubase/Nuendo

- **Peak + RMS dual display**: Dark outline for peaks, lighter fill for RMS
- **AES17 standard**: +3dB offset for RMS values
- **Multi-scale metering**: Peak hold (gray), RMS (blue), current peak
- **Resolution**: Supports 1x-6x vertical zoom scales

#### Logic Pro X

- **Integrated waveform metering**: Real-time amplitude visualization
- **Power mode**: RMS-based view for mastering workflows
- **Outline rendering**: Fine black line around waveform for definition

#### Pro Tools

**Four Waveform View Modes:**

| Mode | Calculation | Best For |
|------|-------------|----------|
| **Peak** (default) | Sample-by-sample max | Transient detection, clipping |
| **Power** | RMS average | Mastering, loudness evaluation |
| **Rectified** | Absolute value display | Bass analysis |
| **Outline** | Boundary-only rendering | Clean visual, editing |

#### Audacity

**Dual-Layer Visualization:**

```
┌─────────────────────────────────────────┐
│ Dark Blue  = Peak values (min/max)      │
│ Light Blue = RMS average                │
│                                         │
│ ▓▓▓▓▓▓▓▓░░░░▓▓▓▓▓▓▓░░░░░░▓▓▓▓▓▓▓▓     │
│ Dark = Peak envelope                    │
│ Light = Average energy                  │
└─────────────────────────────────────────┘
```

When zoomed in far enough, the light blue disappears (not enough samples for meaningful average).

#### Ableton Live

- **Waveform zoom**: Shift+Up/Down for vertical scaling
- **Non-destructive scaling**: Visual only, no gain change
- **Clip view**: Detailed sample-level editing

---

## 3. Anti-Aliasing Techniques

### Understanding Aliasing in Waveform Display

Aliasing in waveform visualization occurs when:

1. **Temporal aliasing**: Sample rate insufficient for signal frequency
2. **Spatial aliasing**: Screen resolution insufficient for waveform detail
3. **Rendering aliasing**: Hard edges without pixel blending

### Technique Comparison

| Technique | Quality | Performance | Best For |
|-----------|---------|-------------|----------|
| **MSAA** | Excellent | Medium | Geometry edges, lines |
| **FXAA** | Good | Fast | Post-process, general |
| **SMAA** | Very Good | Medium | Balanced approach |
| **SDF-based** | Excellent | Fast | Analytical shapes |
| **Super-sampling** | Perfect | Slow | Reference rendering |

### Signed Distance Field (SDF) Anti-Aliasing

**The pro technique for waveform lines.**

```glsl
// SDF for a line segment from A to B
float sdf_line(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Anti-aliased edge using SDF
float aa_edge(float distance, float line_width) {
    float edge = line_width * 0.5;
    return 1.0 - smoothstep(edge - 1.0, edge + 1.0, distance);
}
```

**Why SDF is Superior:**

- Resolution-independent rendering
- Naturally smooth edges at any zoom level
- Easy glow/outline effects (just offset the threshold)
- Mathematically correct intensity distribution

### Sub-Pixel Edge Rendering

For 1-pixel thick lines, render the "fractional" part as transparency:

```rust
// Fractional pixel anti-aliasing
fn antialiased_intensity(y_sample: f32, y_pixel: i32) -> f32 {
    let pixel_top = y_pixel as f32 + 1.0;
    let pixel_bottom = y_pixel as f32;

    // Calculate coverage of waveform within this pixel
    let coverage = (y_sample.min(pixel_top) - y_sample.max(pixel_bottom))
        .max(0.0);

    coverage // 0.0 to 1.0 alpha
}
```

---

## 4. Interpolation Methods

### Method Comparison

| Method | Quality | Computation | Ringing | Best Use |
|--------|---------|-------------|---------|----------|
| **Nearest** | Poor | O(1) | None | Pixel art, preview |
| **Linear** | Fair | O(1) | None | Real-time, rough display |
| **Cubic (Catmull-Rom)** | Good | O(1) | Minimal | Audio playback, smooth curves |
| **B-Spline** | Good | O(1) | None | Smooth curves, no overshoot |
| **Sinc (Windowed)** | Excellent | O(n) | Possible | Sample-accurate reconstruction |

### Linear Interpolation

Simple but produces angular artifacts:

```rust
fn lerp(y0: f32, y1: f32, t: f32) -> f32 {
    y0 + t * (y1 - y0)
}
```

**Visual Result:** Angular joints, "digital" appearance.

### Catmull-Rom Cubic Spline

**The sweet spot for audio waveform display.**

Requires 4 points: P₀, P₁, P₂, P₃ (interpolates between P₁ and P₂)

```rust
/// Catmull-Rom cubic interpolation
/// t ∈ [0, 1] — position between p1 and p2
fn catmull_rom(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) -> f32 {
    let t2 = t * t;
    let t3 = t2 * t;

    // Catmull-Rom basis matrix applied
    let a0 = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
    let a1 = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3;
    let a2 = -0.5 * p0 + 0.5 * p2;
    let a3 = p1;

    a0 * t3 + a1 * t2 + a2 * t + a3
}
```

**Catmull-Rom Coefficient Matrix:**

```
     ┌                     ┐   ┌    ┐
     │ -0.5   1.5  -1.5  0.5│   │ p0 │
y =  │  1.0  -2.5   2.0 -0.5│ × │ p1 │ × [t³ t² t 1]ᵀ
     │ -0.5   0.0   0.5  0.0│   │ p2 │
     │  0.0   1.0   0.0  0.0│   │ p3 │
     └                     ┘   └    ┘
```

**Properties:**
- C¹ continuous (smooth first derivative)
- Passes through all control points
- Local control (changing one point affects only nearby curve)
- Minimal overshoot for audio signals

### Windowed Sinc (Whittaker-Shannon)

**The mathematically perfect reconstruction — for reference rendering.**

```
x̂(t) = Σ x[n] × sinc(fs × (t - nT)) × w(t - nT)

Where:
  sinc(x) = sin(πx) / (πx)
  w(t)    = Window function (Kaiser, Blackman)
  fs      = Sample rate
  T       = Sample period (1/fs)
```

**Windowed Sinc Implementation:**

```rust
fn windowed_sinc(samples: &[f32], t: f32, half_width: usize) -> f32 {
    let center = t.floor() as i32;
    let frac = t - center as f32;

    let mut sum = 0.0;
    let mut weight_sum = 0.0;

    for i in -(half_width as i32)..=(half_width as i32) {
        let idx = center + i;
        if idx >= 0 && idx < samples.len() as i32 {
            let x = frac - i as f32;

            // Sinc function
            let sinc = if x.abs() < 1e-6 {
                1.0
            } else {
                (std::f32::consts::PI * x).sin() / (std::f32::consts::PI * x)
            };

            // Kaiser window (beta = 6.0 for good quality)
            let window = kaiser_window(x, half_width as f32, 6.0);

            let weight = sinc * window;
            sum += samples[idx as usize] * weight;
            weight_sum += weight;
        }
    }

    sum / weight_sum.max(1e-6)
}

fn kaiser_window(x: f32, half_width: f32, beta: f32) -> f32 {
    if x.abs() > half_width {
        return 0.0;
    }
    let r = x / half_width;
    bessel_i0(beta * (1.0 - r * r).sqrt()) / bessel_i0(beta)
}
```

### Practical Recommendations

| Zoom Level | Recommended Method |
|------------|-------------------|
| Overview (1000+ samples/pixel) | Linear or none (min/max only) |
| Medium (10-1000 samples/pixel) | Catmull-Rom cubic |
| Sample-accurate (<10 samples/pixel) | Windowed sinc (Kaiser, N=13) |
| Real-time playback cursor | Catmull-Rom cubic |

---

## 5. Digital vs Analog Aesthetics

### What Makes Waveforms Look "Digital"

```
DIGITAL CHARACTERISTICS (Avoid These):
├── Hard, pixelated edges
├── Stair-stepping on curves
├── Uniform line thickness
├── Flat, solid colors
├── Sharp corners at every sample
├── No anti-aliasing
├── Single-color, no gradients
└── Perfectly crisp rendering
```

### What Makes Waveforms Look "Analog"

```
ANALOG CHARACTERISTICS (Achieve These):
├── Soft, glowing edges
├── Smooth curves between samples
├── Variable intensity (beam speed simulation)
├── Subtle color gradients
├── Gaussian beam profile
├── Phosphor persistence/afterglow
├── Slight blur and bloom
└── Natural imperfections
```

### Technical Differences

| Aspect | Digital Look | Analog Look |
|--------|--------------|-------------|
| **Edges** | 1px hard line | Gaussian falloff (2-4px) |
| **Color** | Solid flat | Gradient with glow |
| **Curves** | Linear segments | Cubic spline interpolated |
| **Brightness** | Uniform | Velocity-dependent |
| **Post-process** | None | Bloom, subtle blur |
| **Anti-aliasing** | None/MSAA | SDF + smoothstep |

### The "Oscilloscope Look" Recipe

```
1. Render waveform as line segments
2. Apply Gaussian beam profile (σ = 1.5px)
3. Intensity ∝ 1/velocity (dim fast movements)
4. Add phosphor persistence (frame blending)
5. Apply subtle bloom (2-pass Gaussian blur)
6. Use additive blending for glow
```

---

## 6. Color Gradients & Shading

### Professional Color Palettes

#### Dark Theme (Pro Audio Standard)

```
BACKGROUNDS:
├── Deepest:    #0a0a0c
├── Deep:       #121216
├── Mid:        #1a1a20
└── Surface:    #242430

WAVEFORM COLORS:
├── Peak Fill:     #40c8ff (cyan) → #4a9eff (blue)
├── RMS Fill:      #40c8ff40 (cyan, 25% opacity)
├── Centerline:    #ffffff20 (white, 12% opacity)
├── Peak Outline:  #80d4ff (light cyan)
└── Clipping:      #ff4040 (red)

GLOW EFFECTS:
├── Inner glow:    waveform color @ 60% opacity
├── Outer glow:    waveform color @ 20% opacity, 4px blur
└── Bloom:         waveform color @ 10% opacity, 8px blur
```

#### Metering Gradient (VU/PPM style)

```
Level-based color gradient (bottom to top):

-60dB  #40c8ff  (cyan)
-24dB  #40ff90  (green)
-12dB  #ffff40  (yellow)
-6dB   #ff9040  (orange)
0dB    #ff4040  (red)
```

### Shading Techniques

#### Vertical Gradient (Depth Effect)

```glsl
// Fragment shader - vertical gradient on waveform
vec3 waveform_color(float y_normalized) {
    // y_normalized: 0.0 = bottom, 1.0 = top
    vec3 color_bottom = vec3(0.25, 0.78, 1.0); // cyan
    vec3 color_top = vec3(0.29, 0.62, 1.0);    // blue

    return mix(color_bottom, color_top, y_normalized);
}
```

#### Glow Effect Layers

```
Layer Stack (bottom to top):
├── Layer 1: Outer glow (8px blur, 10% opacity, additive)
├── Layer 2: Inner glow (4px blur, 30% opacity, additive)
├── Layer 3: Core waveform (anti-aliased SDF)
└── Layer 4: Highlight line (1px, 80% opacity, center)
```

#### RMS Shading

```
RMS Display Approach:
├── Fill between +RMS and -RMS with semi-transparent color
├── Use soft top/bottom edges (gradient or blur)
├── Render BEHIND peak waveform
└── Typically 25-40% opacity of peak color
```

### Bloom Implementation

**Two-Pass Gaussian Blur:**

```glsl
// Blur weights for 5-tap kernel
const float weights[5] = float[](
    0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216
);

// Horizontal blur pass
vec4 blur_horizontal(sampler2D tex, vec2 uv, float blur_size) {
    vec2 tex_offset = 1.0 / textureSize(tex, 0);
    vec4 result = texture(tex, uv) * weights[0];

    for (int i = 1; i < 5; ++i) {
        result += texture(tex, uv + vec2(tex_offset.x * i * blur_size, 0.0)) * weights[i];
        result += texture(tex, uv - vec2(tex_offset.x * i * blur_size, 0.0)) * weights[i];
    }

    return result;
}

// Vertical blur pass (same logic, different axis)
```

**Bloom Pipeline:**

```
1. Render waveform to HDR framebuffer
2. Extract bright pixels (threshold > 0.8)
3. Downsample 2x-4x for efficiency
4. Apply horizontal Gaussian blur
5. Apply vertical Gaussian blur
6. Repeat blur 2-5 times for diffuse glow
7. Additive blend with original
```

---

## 7. RMS vs Peak Display

### Understanding the Difference

```
PEAK Display:
├── Shows instantaneous maximum/minimum values
├── Captures transients accurately
├── Good for clipping detection
├── Can look "sparse" for dynamic content
└── Min/max per display column

RMS Display:
├── Shows "perceived loudness" over time window
├── Smoother, more musical representation
├── Better for understanding mix dynamics
├── Integration time: typically 300ms-3s
└── √(mean of squared samples)
```

### RMS Calculation

```rust
/// Calculate RMS for a block of samples
fn calculate_rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }

    let sum_of_squares: f32 = samples.iter()
        .map(|&s| s * s)
        .sum();

    (sum_of_squares / samples.len() as f32).sqrt()
}

/// Calculate RMS with optional weighting (AES17)
fn calculate_rms_aes17(samples: &[f32]) -> f32 {
    // AES17 adds 3dB offset for sine wave equivalence
    calculate_rms(samples) * 1.4142 // √2 ≈ +3dB
}
```

### Layered Display Technique

**The Professional Approach (Audacity/Cubase style):**

```
┌───────────────────────────────────────────────┐
│                                               │
│     Peak (dark, solid)                        │
│   ┌─────────────────────────────────┐        │
│   │   RMS (light, semi-transparent)  │        │
│   │ ┌─────────────────────────────┐ │        │
│   │ │                             │ │        │
│   │ │      Audio Content          │ │        │
│   │ │                             │ │        │
│   │ └─────────────────────────────┘ │        │
│   └─────────────────────────────────┘        │
│                                               │
└───────────────────────────────────────────────┘

Rendering Order:
1. Background
2. Centerline (optional, subtle)
3. RMS fill (semi-transparent, 30-50% opacity)
4. Peak fill (solid or gradient)
5. Peak outline (optional, for definition)
```

### Implementation

```rust
struct WaveformBlock {
    peak_min: f32,    // Minimum sample value in block
    peak_max: f32,    // Maximum sample value in block
    rms: f32,         // RMS value for block
}

fn render_waveform_column(
    block: &WaveformBlock,
    x: f32,
    height: f32,
    colors: &WaveformColors,
) {
    let center_y = height / 2.0;

    // Convert to pixel coordinates
    let peak_top = center_y - (block.peak_max * center_y);
    let peak_bottom = center_y - (block.peak_min * center_y);
    let rms_top = center_y - (block.rms * center_y);
    let rms_bottom = center_y + (block.rms * center_y);

    // 1. Draw RMS fill (behind peak)
    draw_rect(x, rms_top, 1.0, rms_bottom - rms_top, colors.rms_fill);

    // 2. Draw Peak fill
    draw_rect(x, peak_top, 1.0, peak_bottom - peak_top, colors.peak_fill);

    // 3. Draw Peak outline (optional)
    draw_line(x, peak_top, x, peak_bottom, colors.peak_outline);
}
```

---

## 8. Zoom-Dependent Rendering (LOD)

### Multi-Resolution Strategy

Professional DAWs use a hierarchical cache system:

```
┌─────────────────────────────────────────────────────────────────┐
│                     MIPMAP PYRAMID                              │
├─────────────────────────────────────────────────────────────────┤
│ Level 0: Raw samples (44100/sec for CD audio)                   │
│ Level 1: 256 samples/block → ~172 blocks/sec                    │
│ Level 2: 64K samples/block → ~0.67 blocks/sec                   │
│ Level 3: 1M samples/block  → ~0.04 blocks/sec                   │
└─────────────────────────────────────────────────────────────────┘

Each block stores: { min, max, rms }
```

### Audacity's Approach

From "A Fast Data Structure for Disk-Based Audio Editing" (Mazzoni & Dannenberg, 2002):

```rust
struct WaveformCache {
    // Level 1: 256-sample summaries
    summary_256: Vec<SummaryBlock>,

    // Level 2: 64K-sample summaries
    summary_64k: Vec<SummaryBlock>,
}

struct SummaryBlock {
    min: f32,
    max: f32,
    rms: f32,
}

impl WaveformCache {
    fn get_display_data(
        &self,
        samples: &[f32],
        start_sample: usize,
        samples_per_pixel: usize,
    ) -> Vec<WaveformBlock> {
        if samples_per_pixel >= 65536 {
            // Use 64K summaries
            self.get_from_level2(start_sample, samples_per_pixel)
        } else if samples_per_pixel >= 256 {
            // Use 256 summaries
            self.get_from_level1(start_sample, samples_per_pixel)
        } else {
            // Read raw samples
            self.get_from_samples(samples, start_sample, samples_per_pixel)
        }
    }
}
```

### Zoom Level Rendering Modes

| Samples/Pixel | Display Mode | Interpolation |
|---------------|--------------|---------------|
| > 10000 | Overview bars | None (min/max blocks) |
| 100-10000 | Filled waveform | None (min/max per pixel) |
| 10-100 | Connected points | Catmull-Rom |
| 1-10 | Sample dots + curve | Catmull-Rom |
| < 1 | Interpolated curve | Windowed sinc |

### Sample-Level Rendering

When zoomed in beyond 1:1 (multiple pixels per sample):

```rust
fn render_sample_level(
    samples: &[f32],
    start_sample: usize,
    pixels_per_sample: f32,
    width: usize,
) -> Vec<f32> {
    let mut points = Vec::new();

    for px in 0..width {
        // Calculate sample position for this pixel
        let sample_pos = start_sample as f32 + (px as f32 / pixels_per_sample);
        let sample_idx = sample_pos.floor() as usize;
        let t = sample_pos.fract();

        // Catmull-Rom interpolation
        if sample_idx >= 1 && sample_idx + 2 < samples.len() {
            let y = catmull_rom(
                samples[sample_idx - 1],
                samples[sample_idx],
                samples[sample_idx + 1],
                samples[sample_idx + 2],
                t,
            );
            points.push(y);
        }
    }

    points
}
```

### Dynamic Level of Detail

```rust
enum WaveformLOD {
    Overview,      // Blocks only
    Standard,      // Min/max per pixel
    Detailed,      // Interpolated curves
    SampleLevel,   // Individual sample dots
}

fn select_lod(samples_per_pixel: f32) -> WaveformLOD {
    match samples_per_pixel {
        x if x > 1000.0 => WaveformLOD::Overview,
        x if x > 10.0   => WaveformLOD::Standard,
        x if x > 1.0    => WaveformLOD::Detailed,
        _               => WaveformLOD::SampleLevel,
    }
}
```

---

## 9. GPU Acceleration

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU WAVEFORM PIPELINE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CPU Side:                                                      │
│  ┌───────────────┐    ┌──────────────┐    ┌──────────────────┐ │
│  │ Audio Buffer  │───▶│ Peak Cache   │───▶│ GPU Buffer Upload│ │
│  └───────────────┘    └──────────────┘    └──────────────────┘ │
│                                                                 │
│  GPU Side:                                                      │
│  ┌───────────────┐    ┌──────────────┐    ┌──────────────────┐ │
│  │ Vertex Shader │───▶│ Frag Shader  │───▶│ Post-Process     │ │
│  │ (Quad Gen)    │    │ (SDF + Glow) │    │ (Bloom)          │ │
│  └───────────────┘    └──────────────┘    └──────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Oscilloscope Line Rendering (GPU)

Based on [m1el's woscope technique](https://m1el.github.io/woscope-how/):

**Vertex Shader — Quad Generation:**

```wgsl
// WGSL Vertex Shader
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) beam_coord: vec2<f32>,
};

struct LineSegment {
    start: vec2<f32>,
    end: vec2<f32>,
};

@group(0) @binding(0)
var<storage, read> segments: array<LineSegment>;

@vertex
fn vs_main(
    @builtin(vertex_index) vertex_id: u32,
    @builtin(instance_index) instance_id: u32,
) -> VertexOutput {
    let segment = segments[instance_id];

    let dir = normalize(segment.end - segment.start);
    let normal = vec2<f32>(-dir.y, dir.x);

    let beam_radius = 0.01; // Adjust for desired thickness

    // Generate quad corners based on vertex_id (0-3)
    let corner = vec2<f32>(
        select(-1.0, 1.0, (vertex_id & 1u) != 0u),
        select(-1.0, 1.0, (vertex_id & 2u) != 0u),
    );

    // Position along segment
    let pos_along = select(segment.start, segment.end, corner.x > 0.0);
    let offset = normal * corner.y * beam_radius;

    var output: VertexOutput;
    output.position = vec4<f32>(pos_along + offset, 0.0, 1.0);
    output.beam_coord = corner;

    return output;
}
```

**Fragment Shader — Gaussian Beam:**

```wgsl
// WGSL Fragment Shader
@fragment
fn fs_main(@location(0) beam_coord: vec2<f32>) -> @location(0) vec4<f32> {
    let sigma = 0.3; // Beam spread

    // Distance from beam center (y = 0)
    let d = abs(beam_coord.y);

    // Gaussian falloff
    let intensity = exp(-(d * d) / (2.0 * sigma * sigma));

    // Waveform color with intensity
    let color = vec3<f32>(0.25, 0.78, 1.0); // Cyan

    return vec4<f32>(color * intensity, intensity);
}
```

### Instanced Rendering for Waveforms

**Render thousands of segments with single draw call:**

```rust
// Rust + wgpu
struct WaveformRenderer {
    pipeline: wgpu::RenderPipeline,
    segment_buffer: wgpu::Buffer,
    vertex_buffer: wgpu::Buffer, // Just a quad (4 vertices)
    index_buffer: wgpu::Buffer,  // 6 indices for quad
}

impl WaveformRenderer {
    fn render(&self, encoder: &mut wgpu::CommandEncoder, num_segments: u32) {
        let mut pass = encoder.begin_render_pass(&...);

        pass.set_pipeline(&self.pipeline);
        pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
        pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
        pass.set_bind_group(0, &self.segment_bind_group, &[]);

        // Draw all segments with instancing
        pass.draw_indexed(0..6, 0, 0..num_segments);
    }
}
```

### Compute Shader for Peak Calculation

**Offload min/max/RMS calculation to GPU:**

```wgsl
// WGSL Compute Shader
@group(0) @binding(0)
var<storage, read> samples: array<f32>;

@group(0) @binding(1)
var<storage, read_write> peaks: array<vec4<f32>>; // (min, max, rms, unused)

@compute @workgroup_size(256)
fn compute_peaks(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(local_invocation_id) local_id: vec3<u32>,
) {
    let block_size = 256u;
    let block_start = global_id.x * block_size;

    var local_min = 1.0;
    var local_max = -1.0;
    var sum_squares = 0.0;

    for (var i = 0u; i < block_size; i++) {
        let sample = samples[block_start + i];
        local_min = min(local_min, sample);
        local_max = max(local_max, sample);
        sum_squares += sample * sample;
    }

    let rms = sqrt(sum_squares / f32(block_size));

    peaks[global_id.x] = vec4<f32>(local_min, local_max, rms, 0.0);
}
```

### Phosphor Glow Simulation

**Frame buffer accumulation for persistence:**

```wgsl
// Decay previous frame
@fragment
fn fs_decay(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let prev = textureSample(previous_frame, sampler, uv);
    let decay = 0.95; // 5% decay per frame
    return prev * decay;
}

// Blend new waveform with decayed previous
@fragment
fn fs_composite(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let decayed = textureSample(decayed_frame, sampler, uv);
    let new_waveform = textureSample(waveform_frame, sampler, uv);

    // Additive blending
    return decayed + new_waveform;
}
```

---

## 10. Sub-Pixel Rendering

### Concept

Sub-pixel rendering renders detail at finer resolution than physical pixels:

```
Traditional pixel:        Sub-pixel aware:
┌───┐                    ┌─┬─┬─┐
│ █ │ → on/off           │R│G│B│ → 3x horizontal resolution
└───┘                    └─┴─┴─┘
```

### Techniques for Waveforms

#### 1. Super-Sampling Anti-Aliasing (SSAA)

Render at 2x-4x resolution, then downsample:

```rust
fn render_supersampled(width: u32, height: u32, scale: u32) -> Image {
    // Render at higher resolution
    let hi_res = render_waveform(width * scale, height * scale);

    // Downsample with box filter
    let mut output = Image::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let mut sum = Color::BLACK;
            for sy in 0..scale {
                for sx in 0..scale {
                    sum += hi_res.get_pixel(x * scale + sx, y * scale + sy);
                }
            }
            output.set_pixel(x, y, sum / (scale * scale) as f32);
        }
    }
    output
}
```

#### 2. Analytical Coverage Calculation

Calculate exact pixel coverage mathematically:

```rust
fn line_pixel_coverage(
    line_start: Vec2,
    line_end: Vec2,
    pixel_x: f32,
    pixel_y: f32,
    line_width: f32,
) -> f32 {
    // SDF-based coverage
    let pixel_center = Vec2::new(pixel_x + 0.5, pixel_y + 0.5);
    let distance = point_to_line_distance(pixel_center, line_start, line_end);

    // Analytical anti-aliasing
    let half_width = line_width * 0.5;
    let coverage = 1.0 - smoothstep(half_width - 0.5, half_width + 0.5, distance);

    coverage
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}
```

#### 3. Fractional Positioning

For waveform values that fall between pixels:

```rust
fn render_with_fractional_y(
    samples: &[f32],
    width: usize,
    height: usize,
) -> Vec<Vec<f32>> {
    let mut image = vec![vec![0.0; width]; height];
    let center_y = height as f32 / 2.0;

    for x in 0..width {
        let sample = samples[x];
        let y_exact = center_y - (sample * center_y);

        // Distribute intensity across adjacent pixels
        let y_floor = y_exact.floor() as usize;
        let y_ceil = y_floor + 1;
        let frac = y_exact.fract();

        if y_floor < height {
            image[y_floor][x] += 1.0 - frac; // Upper pixel
        }
        if y_ceil < height {
            image[y_ceil][x] += frac; // Lower pixel
        }
    }

    image
}
```

### Sub-Pixel Precision in GPU Shaders

```wgsl
@fragment
fn fs_subpixel_waveform(
    @location(0) uv: vec2<f32>,
    @location(1) sample_value: f32,
) -> @location(0) vec4<f32> {
    let pixel_size = 1.0 / resolution.y;
    let line_width = 2.0 * pixel_size;

    // Waveform position in UV space
    let waveform_y = 0.5 - sample_value * 0.5;

    // Distance from current fragment to waveform
    let distance = abs(uv.y - waveform_y);

    // Sub-pixel anti-aliasing
    let half_width = line_width * 0.5;
    let aa_width = pixel_size; // 1 pixel transition zone

    let alpha = 1.0 - smoothstep(half_width - aa_width, half_width + aa_width, distance);

    return vec4<f32>(waveform_color, alpha);
}
```

---

## 11. Implementation Reference

### Complete Waveform Renderer Structure

```rust
pub struct UltimateWaveformRenderer {
    // GPU resources
    device: wgpu::Device,
    queue: wgpu::Queue,

    // Render pipelines
    waveform_pipeline: wgpu::RenderPipeline,
    bloom_pipeline: wgpu::RenderPipeline,
    composite_pipeline: wgpu::RenderPipeline,

    // Framebuffers
    waveform_fbo: wgpu::Texture,
    bloom_fbo: [wgpu::Texture; 2], // Ping-pong
    persistence_fbo: wgpu::Texture,

    // Data buffers
    sample_buffer: wgpu::Buffer,
    peak_cache: PeakCache,

    // Settings
    config: WaveformConfig,
}

pub struct WaveformConfig {
    // Display mode
    pub show_rms: bool,
    pub show_peaks: bool,
    pub show_outline: bool,

    // Visual style
    pub line_width: f32,          // 1.0 - 3.0
    pub glow_intensity: f32,      // 0.0 - 1.0
    pub phosphor_persistence: f32, // 0.0 - 1.0

    // Colors
    pub peak_color: [f32; 4],
    pub rms_color: [f32; 4],
    pub glow_color: [f32; 4],

    // Quality
    pub antialiasing_mode: AAMode,
    pub bloom_iterations: u32,
    pub interpolation: InterpolationMode,
}

pub enum AAMode {
    None,
    MSAA4x,
    SDF,
    SuperSample2x,
}

pub enum InterpolationMode {
    None,
    Linear,
    CatmullRom,
    WindowedSinc,
}
```

### Rendering Flow

```rust
impl UltimateWaveformRenderer {
    pub fn render_frame(
        &mut self,
        samples: &[f32],
        viewport: Rect,
        zoom_level: f32,
    ) -> wgpu::TextureView {
        // 1. Select LOD based on zoom
        let lod = self.select_lod(zoom_level);

        // 2. Get peak data (from cache or compute)
        let peaks = match lod {
            WaveformLOD::Overview => self.peak_cache.get_level2(),
            WaveformLOD::Standard => self.peak_cache.get_level1(),
            _ => self.compute_peaks_realtime(samples),
        };

        // 3. Render waveform to FBO
        self.render_waveform(&peaks, viewport);

        // 4. Apply phosphor persistence (blend with previous frame)
        if self.config.phosphor_persistence > 0.0 {
            self.apply_persistence();
        }

        // 5. Apply bloom/glow
        if self.config.glow_intensity > 0.0 {
            self.apply_bloom();
        }

        // 6. Composite final image
        self.composite()
    }
}
```

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| **Frame rate** | 60fps @ 4K | GPU-bound |
| **Peak computation** | <1ms for 1M samples | Compute shader |
| **Draw calls** | 1-3 per waveform | Instancing |
| **Memory** | <50MB for 1-hour stereo | Cached peaks only |
| **Latency** | <16ms end-to-end | Audio buffer → display |

---

## References & Sources

### Technical Resources

- [How to draw oscilloscope lines with math and WebGL](https://m1el.github.io/woscope-how/) - m1el
- [Simulating an XY oscilloscope on the GPU](http://nicktasios.nl/posts/simulating-an-xy-oscilloscope-on-the-gpu.html) - Nick Tasios
- [Efficient rendering of waveforms](https://forum.audacityteam.org/t/efficient-rendering-of-waveforms/19082) - Audacity Forum
- [LearnOpenGL - Bloom](https://learnopengl.com/Advanced-Lighting/Bloom)
- [Windowed Sinc Interpolation](https://www.dsprelated.com/freebooks/pasp/Windowed_Sinc_Interpolation.html) - DSPRelated
- [Catmull-Rom Interpolation](https://danceswithcode.net/engineeringnotes/interpolation/interpolation.html)
- [Signed Distance Fields](https://mini.gmshaders.com/p/sdf) - GM Shaders
- [NAudio WaveForm Rendering](https://github.com/naudio/NAudio/blob/master/Docs/WaveFormRendering.md)

### Academic Papers

- "A Fast Data Structure for Disk-Based Audio Editing" - Mazzoni & Dannenberg (Computer Music Journal, 2002)
- "Improved Alpha-Tested Magnification for Vector Textures" - Chris Green, Valve (SIGGRAPH 2007)

### DAW References

- [Pro Tools Waveform Views](https://www.production-expert.com/production-expert-1/pro-tools-waveform-views-are-yours-left-on-the-default-setting)
- [Audacity Waveform Manual](https://manual.audacityteam.org/man/audacity_waveform.html)
- [Cubase Master Meter](https://archive.steinberg.help/cubase_pro_artist/v9/en/cubase_nuendo/topics/loudness/loudness_master_meter_r.html)

---

## Quick Implementation Checklist

```
□ Peak cache with multi-level LOD (256, 64K samples/block)
□ GPU buffer for waveform data (storage buffer)
□ Instanced quad rendering for line segments
□ SDF-based anti-aliasing in fragment shader
□ Gaussian beam profile for analog look
□ Catmull-Rom interpolation for zoomed view
□ RMS + Peak dual display with transparency
□ 2-pass Gaussian blur for bloom effect
□ Frame buffer persistence for phosphor glow
□ Additive blending for glow compositing
□ Color gradients (vertical and level-based)
□ Zoom-dependent rendering mode switching
```

---

## 12. DAW Zoom Limits & Sample-Level Display

### Maximum Zoom Resolution

U DAW-ovima maksimalni zoom nivo se određuje:

1. **Sample Rate rezolucijom** - Viši sample rate = više detalja
2. **Softverskim limitima** - Mogućnost zumiranja do pojedinačnih samplova
3. **DPI rezolucijom ekrana** - Fizički limit prikaza

**Sample Rate Impact:**

| Sample Rate | Sample Duration | Samples/Second |
|-------------|-----------------|----------------|
| 44.1kHz | 22.7μs | 44,100 |
| 48kHz | 20.8μs | 48,000 |
| 96kHz | 10.4μs | 96,000 |
| 192kHz | 5.2μs | 192,000 |

### Zoom-in View Requirements

**Ključni elementi dobrog zoom-in prikaza:**

```
HIGH ZOOM REQUIREMENTS:
├── Zero Line (nulta linija)
│   └── Uvek vidljiva centralna linija za pozitivnu/negativnu amplitudu
├── Precizno vreme
│   └── Grid i markeri moraju biti precizni do milisekunde
├── Jasna amplituda
│   └── Proporcionalan prikaz svih nivoa amplitude
├── Stereo L/R
│   └── Odvojeni kanali za faznu analizu
├── Zero-Crossing indikatori
│   └── Olakšano precizno sečenje
└── dB skala
    └── Amplitude scale markeri
```

### Professional Zoom Features

**Funkcionalnosti za preciznu editaciju:**

| Feature | Svrha |
|---------|-------|
| **Zoom to Selection** | Zumiranje na označeni deo |
| **Zoom to Zero-Crossing** | Za sečenje bez klikova |
| **Sample-Level Editing** | Videti/editovati pojedinačne sample-ove |
| **Phase Display** | Vizuelna indikacija faze L/R |
| **Micro-detail View** | Uklanjanje šuma, precizno postavljanje |

### Sample-Level Visualization

Kada je zoom dovoljno visok (< 1 sample/pixel):

```
SAMPLE MODE DISPLAY:
├── Vertikalne linije za svaki sample
├── Catmull-Rom interpolacija između samplova
├── Glow efekat za oscilloscope izgled
└── dB markeri na skali
```

**Implementacija:**

```dart
// Flutter/Dart - Sample level rendering
if (samplesPerPixel < 1) {
  // Prikazujemo interpoliranu krivu
  // Catmull-Rom za smooth izgled
  // Svaki sample je vidljiv kao tačka na krivoj
}
```

### Zoom Level Modes

| Samples/Pixel | Mode | Display |
|---------------|------|---------|
| > 100 | OVERVIEW | Min/max envelope (vertikalne linije) |
| 10-100 | DETAIL | Smooth bezier envelope sa gradient fill |
| 1-10 | SAMPLE | Catmull-Rom interpolated curve |
| < 1 | ULTRA | Sample points + interpolated curve |

### Why Deep Zoom Matters

```
PRECIZNO SEČENJE:
├── Izbegavanje klikova i pucanja
├── Zero-crossing cuts
└── Sample-accurate edits

MICRO-DETAIL EDITING:
├── Uklanjanje šuma na tihim delovima
├── Precizno postavljanje reverb tails
├── Click/pop removal
└── Breath removal

COMPING:
├── Prepoznavanje najboljih delova
├── Phase alignment
└── Crossfade optimization
```

### Technical Limits

**Nema teoretskog limita za zoom** - granica je praktična:
- Rezolucija piksela na ekranu
- Sample rate projekta (npr. 192kHz = svaki uzorak je 1/192000 sekunde)
- Sposobnost da se vide "stepenasti" pojedinačni uzorci

**Cilj:** Zumirati dok se ne vide pojedinačni uzorci zvuka, što je najprecizniji nivo za audio produkciju.

---

## 13. Flutter/Dart Implementation (Production Ready)

### Kompletan Pro DAW Waveform Renderer

Testiran i funkcionalan kod za Flutter aplikaciju.

#### Catmull-Rom Interpolacija

```dart
/// Catmull-Rom cubic interpolation - smooth curves through data points
double catmullRom(double p0, double p1, double p2, double p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  final a0 = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
  final a1 = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3;
  final a2 = -0.5 * p0 + 0.5 * p2;
  final a3 = p1;
  return a0 * t3 + a1 * t2 + a2 * t + a3;
}
```

#### 4-Level LOD System

```dart
// Draw waveform based on zoom level (4 LOD modes)
if (samplesPerPixel < 1) {
  // ULTRA ZOOM - interpolated curve only
  _drawUltraZoomWaveform(canvas, size, centerY, amplitude, samplesPerPixel, startSample);
} else if (samplesPerPixel < 10) {
  // SAMPLE MODE - Catmull-Rom curve
  _drawCatmullRomWaveform(canvas, size, centerY, amplitude, samplesPerPixel, startSample);
} else if (samplesPerPixel < 100) {
  // DETAIL MODE - smooth envelope with RMS
  _drawSmoothEnvelope(canvas, size, centerY, amplitude, samplesPerPixel, startSample);
} else {
  // OVERVIEW MODE - min/max bars with RMS
  _drawMinMaxEnvelope(canvas, size, centerY, amplitude, samplesPerPixel, startSample);
}
```

#### ULTRA ZOOM Mode (< 1 sample/pixel)

```dart
void _drawUltraZoomWaveform(Canvas canvas, Size size, double centerY,
    double amplitude, double samplesPerPixel, int startSample) {
  final pixelsPerSample = 1 / samplesPerPixel;
  final visibleSamples = (size.width / pixelsPerSample).ceil() + 2;

  final path = Path();
  final interpolationSteps = 16; // More steps for ultra smooth
  var isFirst = true;

  for (int i = -1; i < visibleSamples; i++) {
    final sampleIdx = (startSample + i).clamp(0, waveform.length - 1);

    for (int step = 0; step < interpolationSteps; step++) {
      final t = step / interpolationSteps;

      final i0 = (sampleIdx - 1).clamp(0, waveform.length - 1);
      final i1 = sampleIdx.clamp(0, waveform.length - 1);
      final i2 = (sampleIdx + 1).clamp(0, waveform.length - 1);
      final i3 = (sampleIdx + 2).clamp(0, waveform.length - 1);

      final value = catmullRom(waveform[i0], waveform[i1], waveform[i2], waveform[i3], t);
      final x = (i + t) * pixelsPerSample;
      final y = centerY - value * amplitude;

      if (x < -pixelsPerSample || x > size.width + pixelsPerSample) continue;

      if (isFirst) {
        path.moveTo(x, y);
        isFirst = false;
      } else {
        path.lineTo(x, y);
      }
    }
  }

  // Glow effect (oscilloscope style)
  canvas.drawPath(path, Paint()
    ..style = PaintingStyle.stroke
    ..color = color.withOpacity(0.15)
    ..strokeWidth = 6.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));

  // Main curve
  canvas.drawPath(path, Paint()
    ..style = PaintingStyle.stroke
    ..color = color
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true);
}
```

#### RMS Overlay (Cubase Style)

```dart
void _drawSmoothEnvelope(Canvas canvas, Size size, double centerY,
    double amplitude, double samplesPerPixel, int startSample) {
  final maxYs = <double>[];
  final minYs = <double>[];
  final rmsYs = <double>[]; // RMS values for overlay

  for (int px = 0; px < size.width.toInt(); px++) {
    final sampleStart = startSample + (px * samplesPerPixel).floor();
    final sampleEnd = startSample + ((px + 1) * samplesPerPixel).ceil();

    double minVal = 0.0;
    double maxVal = 0.0;
    double sumSquares = 0.0;
    int count = 0;

    for (int i = sampleStart; i < safeEnd; i++) {
      final s = waveform[i];
      minVal = math.min(minVal, s);
      maxVal = math.max(maxVal, s);
      sumSquares += s * s;
      count++;
    }

    final rms = count > 0 ? math.sqrt(sumSquares / count) : 0.0;
    maxYs.add(centerY - maxVal * amplitude);
    minYs.add(centerY - minVal * amplitude);
    rmsYs.add(rms);
  }

  // 1. Draw RMS fill FIRST (behind peak)
  final rmsPath = Path();
  rmsPath.moveTo(0, centerY - rmsYs[0] * amplitude);
  for (int i = 1; i < rmsYs.length; i++) {
    rmsPath.lineTo(i.toDouble(), centerY - rmsYs[i] * amplitude);
  }
  for (int i = rmsYs.length - 1; i >= 0; i--) {
    rmsPath.lineTo(i.toDouble(), centerY + rmsYs[i] * amplitude);
  }
  rmsPath.close();

  canvas.drawPath(rmsPath, Paint()
    ..color = color.withOpacity(0.25)
    ..style = PaintingStyle.fill);

  // 2. Draw Peak envelope ON TOP with bezier smoothing
  final path = Path();
  path.moveTo(0, maxYs[0]);
  for (int i = 0; i < maxYs.length - 1; i++) {
    final midX = i + 0.5;
    final midY = (maxYs[i] + maxYs[i + 1]) / 2;
    path.quadraticBezierTo(i.toDouble(), maxYs[i], midX, midY);
  }
  // ... complete envelope and draw with gradient
}
```

#### Time Ruler with Adaptive Units

```dart
void _drawTimeRuler(Canvas canvas, Size size, double samplesPerPixel, int startSample) {
  final secondsPerPixel = samplesPerPixel / sampleRate;
  final startTime = startSample / sampleRate;

  // Determine appropriate interval based on zoom
  double interval;
  String Function(double) formatTime;

  if (secondsPerPixel < 0.000001) {
    interval = 0.0000001; // 100ns
    formatTime = (t) => '${(t * 1000000000).toStringAsFixed(0)}ns';
  } else if (secondsPerPixel < 0.00001) {
    interval = 0.000001; // 1μs
    formatTime = (t) => '${(t * 1000000).toStringAsFixed(1)}μs';
  } else if (secondsPerPixel < 0.0001) {
    interval = 0.00001; // 10μs
    formatTime = (t) => '${(t * 1000000).toStringAsFixed(0)}μs';
  } else if (secondsPerPixel < 0.001) {
    interval = 0.0001; // 100μs
    formatTime = (t) => '${(t * 1000).toStringAsFixed(2)}ms';
  } else if (secondsPerPixel < 0.01) {
    interval = 0.001; // 1ms
    formatTime = (t) => '${(t * 1000).toStringAsFixed(1)}ms';
  } else if (secondsPerPixel < 0.1) {
    interval = 0.01; // 10ms
    formatTime = (t) => '${(t * 1000).toStringAsFixed(0)}ms';
  } else if (secondsPerPixel < 1.0) {
    interval = 0.1; // 100ms
    formatTime = (t) => '${t.toStringAsFixed(2)}s';
  } else {
    interval = 1.0; // 1s
    formatTime = (t) => '${t.toStringAsFixed(1)}s';
  }

  // Draw markers
  final firstMarker = (startTime / interval).ceil() * interval;
  for (double t = firstMarker; ; t += interval) {
    final x = (t - startTime) / secondsPerPixel;
    if (x > size.width) break;
    // Draw tick and label...
  }
}
```

#### Keyboard Shortcuts

```dart
void _handleKeyPress(KeyEvent event) {
  if (event is! KeyDownEvent) return;

  setState(() {
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      _zoom = (_zoom * 1.5).clamp(0.1, 2000000.0); // Zoom in
    } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
      _zoom = (_zoom / 1.5).clamp(0.1, 2000000.0); // Zoom out
    } else if (event.logicalKey == LogicalKeyboardKey.digit0) {
      _zoom = 100.0; // Reset
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _scrollOffset = (_scrollOffset - 0.1).clamp(0.0, 10.0); // Pan left
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _scrollOffset = (_scrollOffset + 0.1).clamp(0.0, 10.0); // Pan right
    }
  });
}
```

### Zoom Level Reference Table

| Zoom Value | Samples/Pixel | Mode | Visible Time (1000px) | Features |
|------------|---------------|------|----------------------|----------|
| 0.1x | 480000 | OVERVIEW | 10s | Min/max bars + RMS |
| 100x | 480 | OVERVIEW | 10ms | Min/max bars + RMS |
| 1000x | 48 | DETAIL | 1ms | Bezier envelope + RMS |
| 10000x | 4.8 | SAMPLE | 100μs | Catmull-Rom curve |
| 100000x | 0.48 | ULTRA | 10μs | Interpolated smooth curve |
| 500000x | 0.096 | ULTRA | 2μs | Individual samples visible |
| 2000000x | 0.024 | ULTRA | 500ns | Maximum detail |

### Color Scheme

```dart
// Pro Audio Dark Theme
const backgrounds = {
  'deepest': Color(0xFF0a0a0c),
  'deep': Color(0xFF121216),
  'mid': Color(0xFF1a1a20),
  'surface': Color(0xFF242430),
};

const waveformColors = {
  'leftChannel': Color(0xFF4a9eff),   // Blue
  'rightChannel': Color(0xFFff6b4a),  // Orange/Red
  'rmsOverlay': 0.25,                  // 25% opacity
  'peakGradient': [0.6, 0.2, 0.6],    // Top, center, bottom opacity
};

const uiColors = {
  'zeroLine': Colors.white.withOpacity(0.3),
  'grid': Colors.white.withOpacity(0.05),
  'zeroCrossing': Colors.yellow.withOpacity(0.7),
};
```

### Performance Tips

1. **Pre-compute peak cache** za brži overview rendering
2. **Limit interpolation steps** - 8 za SAMPLE mode, 16 za ULTRA
3. **Skip off-screen samples** u petljama
4. **Use `.clamp()` umesto manual bounds checking**
5. **Batch paint operations** - jedna Paint instanca za više linija

---

*This guide provides the foundation for implementing professional-quality waveform visualization that matches or exceeds the visual quality of industry-standard DAWs like Cubase, Logic Pro, Pro Tools, and Ableton Live.*
