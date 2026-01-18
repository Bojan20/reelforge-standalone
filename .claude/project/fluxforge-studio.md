# FluxForge Studio — Project Specification

> Profesionalni standalone audio editor/middleware, Cubase/Wwise nivo.

---

## Vision

**Ultimate audio software for slot game development.**

Kombinacija:
- **DAW** funkcionalnosti (Cubase/Pro Tools)
- **Middleware** integracije (Wwise/FMOD)
- **Plugin** kvaliteta (FabFilter/iZotope)

Za slot industriju — deterministički, compliance-ready, low-latency.

---

## Tech Stack Summary

| Layer | Technology | Purpose |
|-------|------------|---------|
| App Shell | Tauri 2.0 | Native windowing, file I/O |
| GUI | iced 0.13+ | GPU-accelerated UI |
| Graphics | wgpu + WGSL | Visualizations |
| Audio I/O | cpal | Cross-platform audio |
| DSP | Rust + SIMD | Processing |
| Plugins | nih-plug | VST3/AU/CLAP |
| State | serde | Serialization |

**Language ratio:** 96% Rust, 3% WGSL, 1% C

---

## Architecture

### 7-Layer Stack

```
Layer 7: Application Shell (Tauri)
    ↓
Layer 6: GUI Framework (iced)
    ↓
Layer 5: Visualization (wgpu)
    ↓
Layer 4: State Management
    ↓
Layer 3: Audio Engine
    ↓
Layer 2: DSP Processors
    ↓
Layer 1: Audio I/O (cpal)
```

### Crate Structure

```
crates/
├── rf-core/        # Shared types, traits, utilities
├── rf-dsp/         # DSP processors (SIMD optimized)
├── rf-audio/       # Audio I/O (cpal wrapper)
├── rf-engine/      # Audio graph, routing, buses
├── rf-state/       # Undo/redo, presets, automation
├── rf-gui/         # iced widgets (knobs, meters, etc.)
├── rf-viz/         # wgpu visualizations (spectrum, waveform)
└── rf-plugin/      # nih-plug plugin wrappers
```

---

## Core Features

### Audio Engine

- **Dual-Path Processing**
  - Real-time path: <3ms latency
  - Guard path: Async lookahead (like Cubase ASIO-Guard)

- **Graph-Based Routing**
  - Nodes: Sources, Effects, Buses, Master
  - Connections: Flexible routing, sidechain
  - Parallel processing where possible

- **Bus System**
  - 6 buses: UI, REELS, FX, VO, MUSIC, AMBIENT
  - Per-bus: Volume, Pan, Insert chain, Sends
  - Master: Limiter, Dither, Metering

### DSP Processors

| Processor | Features |
|-----------|----------|
| **EQ** | 64 bands, TDF-II biquads, linear/hybrid phase |
| **Compressor** | VCA/Opto/FET modes, sidechain, lookahead |
| **Limiter** | True peak, 4x oversampling, TPDF dither |
| **Gate** | Sidechain filter, range, hysteresis |
| **Reverb** | Convolution + algorithmic hybrid |
| **Delay** | Tempo sync, ping-pong, modulation |
| **Saturator** | Tape, tube, transistor models |

### Plugin System

- **Format Support**
  - VST3 (Windows, macOS, Linux)
  - AU (macOS)
  - CLAP (all platforms)

- **Features**
  - Plugin scanning & caching
  - Preset management
  - Parameter automation
  - Sidechain routing

### State Management

- **Undo/Redo**
  - Command pattern
  - 1000+ levels
  - Grouped operations

- **A/B Comparison**
  - Instant state switch
  - Memory efficient (diff-based)

- **Presets**
  - JSON format with schema validation
  - Categories, tags, favorites
  - Import/export
  - Preset morphing

- **Automation**
  - Sample-accurate
  - Curve types: linear, bezier, step
  - Record, draw, edit modes

### Project Format

```json
{
  "version": "1.0.0",
  "sample_rate": 48000,
  "tracks": [...],
  "buses": [...],
  "master": {...},
  "automation": [...],
  "metadata": {
    "name": "Project Name",
    "author": "...",
    "created": "2025-01-01T00:00:00Z"
  }
}
```

---

## EQ Specification (VanEQ Ultimate)

### Capabilities

| Feature | Spec |
|---------|------|
| Bands | 64 maximum |
| Filter types | Bell, Low/High Shelf, Low/High Pass, Notch, Bandpass, Allpass, Tilt |
| Phase modes | Minimum phase, Linear phase, Hybrid (0-100% blend) |
| Precision | 64-bit double internal |
| Oversampling | 1x, 2x, 4x, 8x, 16x |
| Dynamic EQ | Per-band: threshold, ratio, attack, release, knee |
| M/S Mode | Full mid/side processing |
| Spectrum | GPU FFT, 60fps, 8192-point, pre/post overlay |

### Filter Implementation

- **Biquad Structure:** TDF-II (numerically optimal)
- **Coefficients:** Matched Z-transform (Vicanek method)
- **Linear Phase:** Partitioned FFT convolution
- **SIMD:** AVX-512/AVX2/SSE4.2/NEON runtime dispatch

### UI Features

- **Spectrum Analyzer**
  - Pre/post EQ overlay
  - Freeze mode
  - Peak hold
  - Adjustable range/resolution

- **Band Controls**
  - Drag nodes on graph
  - Right-click for type/options
  - Shift+drag for fine adjustment
  - Alt+drag for Q only
  - Double-click to reset

- **Keyboard Shortcuts**
  - 1-9: Select band
  - A: Add band
  - Delete: Remove band
  - B: Bypass band
  - M/S: Toggle mid/side

---

## Visualization

### Spectrum Analyzer

```wgsl
// spectrum.wgsl — GPU-accelerated spectrum rendering
@group(0) @binding(0) var<storage, read> fft_data: array<f32>;
@group(0) @binding(1) var<uniform> config: SpectrumConfig;

@fragment
fn fs_main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    // Log-frequency mapping
    let freq = pow(10.0, mix(log10(20.0), log10(20000.0), uv.x));

    // Get magnitude from FFT
    let bin = freq_to_bin(freq, config.sample_rate, config.fft_size);
    let magnitude = fft_data[bin];

    // dB conversion
    let db = 20.0 * log10(max(magnitude, 1e-10));
    let normalized = (db - config.min_db) / (config.max_db - config.min_db);

    // Draw if above threshold
    if uv.y < normalized {
        return config.fill_color;
    }
    return vec4<f32>(0.0);
}
```

### Waveform Display

- **LOD System:** Multiple resolution caches
- **GPU Instancing:** For large files
- **Minimap:** Overview navigation

### Meters

| Type | Standard |
|------|----------|
| Peak | Sample + True Peak |
| RMS | 300ms window |
| LUFS | EBU R128 (M, S, I) |
| Correlation | Phase meter |
| Spectrum | Real-time FFT |

---

## Performance Targets

| Metric | Target |
|--------|--------|
| Audio latency | < 3ms @ 128 samples |
| DSP CPU | < 20% @ 44.1kHz stereo |
| GUI framerate | 60fps minimum |
| Memory idle | < 200MB |
| Startup time | < 2s cold |
| Plugin scan | < 5s for 100 plugins |

---

## Visual Design

### Color Palette

```
BACKGROUND:
├── #0a0a0c  deepest (window bg)
├── #121216  deep (panel bg)
├── #1a1a20  mid (control bg)
└── #242430  surface (elevated)

ACCENT:
├── #4a9eff  blue (focus, selection)
├── #ff9040  orange (active, boost)
├── #40ff90  green (positive, ok)
├── #ff4060  red (clip, error)
└── #40c8ff  cyan (spectrum, cut)

METER GRADIENT:
#40c8ff → #40ff90 → #ffff40 → #ff9040 → #ff4040
(cyan)    (green)   (yellow)  (orange)   (red)

TEXT:
├── #ffffff  primary
├── #b0b0c0  secondary
└── #606080  disabled
```

### Typography

- **Primary:** Inter (or system sans-serif)
- **Monospace:** JetBrains Mono (for values)
- **Sizes:** 11px (small), 13px (normal), 16px (headers)

### Animations

| Element | Duration | Easing |
|---------|----------|--------|
| Button hover | 80ms | ease-out |
| Panel transition | 200ms | ease-in-out |
| Meter attack | 5-15ms | linear |
| Meter release | 100-200ms | ease-out |

---

## Platform Support

| Platform | Audio Backend | Notes |
|----------|---------------|-------|
| macOS Intel | CoreAudio | Full support |
| macOS ARM | CoreAudio | Native ARM64 |
| Windows | ASIO, WASAPI | ASIO preferred |
| Linux | JACK, PipeWire | JACK recommended |

### Build Targets

```bash
# macOS
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin

# Windows
cargo build --release --target x86_64-pc-windows-msvc

# Linux
cargo build --release --target x86_64-unknown-linux-gnu
```

---

## Testing Strategy

### Unit Tests

- All DSP processors
- Filter coefficient calculation
- State management operations

### Integration Tests

- Audio graph routing
- Plugin loading/unloading
- Project save/load

### Benchmarks

- DSP processing throughput
- SIMD vs scalar comparison
- Memory allocation tracking

### Reference Tests

- Compare filter output to reference implementations
- Bit-exact where applicable

---

## Roadmap

### Phase 1: Foundation
- [ ] Rust workspace setup
- [ ] rf-core: types and traits
- [ ] rf-audio: cpal integration
- [ ] rf-dsp: biquad filters

### Phase 2: Engine
- [ ] rf-engine: audio graph
- [ ] Bus routing
- [ ] Lock-free communication

### Phase 3: DSP
- [ ] Complete EQ (64-band)
- [ ] Compressor
- [ ] Limiter
- [ ] Metering

### Phase 4: GUI
- [ ] rf-gui: basic widgets
- [ ] rf-viz: spectrum analyzer
- [ ] EQ editor UI

### Phase 5: Integration
- [ ] Tauri shell
- [ ] Project save/load
- [ ] Preset system

### Phase 6: Polish
- [ ] Performance optimization
- [ ] Testing suite
- [ ] Documentation

### Phase 7: Release
- [ ] Plugin builds
- [ ] Installer
- [ ] Website/docs

---

## Reference Implementation

**Stari web projekat:** `~/Desktop/fluxforge-editor/`

Koristiti kao referencu za:
- UI/UX dizajn
- DSP algoritme (prepisati u Rust)
- Color scheme
- Workflow patterns

**NE koristiti** web kod direktno — sve ispočetka u Rust-u.
