## Key Dependencies

### Rust (Cargo.toml workspace)

```toml
[workspace.dependencies]
# Graphics
wgpu = "24.0"
bytemuck = "1.21"

# Audio I/O
cpal = "0.15"
dasp = "0.11"

# DSP
rustfft = "6.2"
realfft = "3.4"

# Plugin hosting
vst3 = "0.3"
rack = "0.4"

# Concurrency
rtrb = "0.3"
parking_lot = "0.12"
rayon = "1.10"
crossbeam-channel = "0.5"

# Serialization
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# Audio file I/O
symphonia = "0.5"
hound = "3.5"

# Utilities
log = "0.4"
thiserror = "2.0"
anyhow = "1.0"

# Flutter-Rust bridge (rf-bridge)
flutter_rust_bridge = "2.7"
tokio = "1.43"
```

### Flutter (pubspec.yaml)

```yaml
dependencies:
  provider: ^6.1.5           # State management
  flutter_rust_bridge: ^2.11.1  # FFI bridge
  flutter_animate: ^4.5.2    # Animations
  just_audio: ^0.9.46        # Audio preview
  file_picker: ^9.2.0        # File dialogs
  web_socket_channel: ^3.0.3 # Live engine connection
```

---

## Build Commands

```bash
# Development
cargo run                    # Debug build
cargo run --release          # Release build

# Testing
cargo test                   # All tests
cargo test -p rf-dsp         # DSP crate only
cargo bench                  # Benchmarks

# Build
cargo build --release
cargo build --release --target x86_64-apple-darwin   # macOS Intel
cargo build --release --target aarch64-apple-darwin  # macOS ARM

# Plugin build
cargo xtask bundle rf-plugin --release  # VST3/AU/CLAP
```

---

## Performance Targets

| Metric         | Target                 | Measurement          |
| -------------- | ---------------------- | -------------------- |
| Audio latency  | < 3ms @ 128 samples    | cpal callback timing |
| DSP load       | < 20% @ 44.1kHz stereo | CPU profiler         |
| GUI frame rate | 60fps minimum          | Flutter DevTools     |
| Memory         | < 200MB idle           | System monitor       |
| Startup time   | < 2s cold start        | Wall clock           |

---

## EQ Specifications (ProEq — Unified Superset, 2026-02-17)

| Feature      | Spec                                                  |
| ------------ | ----------------------------------------------------- |
| Bands        | 64 (vs Pro-Q's 24)                                    |
| Filter types | 10 (bell, shelf, cut, notch, tilt, bandpass, allpass) |
| Phase modes  | Minimum, Linear, Hybrid (blend)                       |
| Precision    | 64-bit double internal                                |
| Oversampling | 1x, 2x, 4x, 8x, 16x (per-band, OversampleMode enum)  |
| Spectrum     | 512-bin FFT, 60fps, 1/3 octave smoothing, Catmull-Rom spline |
| Dynamic EQ   | Per-band threshold, ratio, attack, release            |
| Mid/Side     | Full M/S processing                                   |
| Auto-gain    | ITU-R BS.1770-4 loudness matching                     |
| MZT Filters  | Per-band Matched Z-Transform (optional, from UltraEq) |
| Transient-Aware | Per-band Q reduction during transients (TransientDetector) |
| Per-band Saturation | HarmonicSaturator per band (drive/mix/type)     |
| Equal Loudness | Global Fletcher-Munson curve compensation            |
| Correlation  | Global L/R phase correlation metering                  |
| Freq Analysis | Global spectral analysis with suggestions             |

**Note:** ProEq is now the ONLY production EQ — UltraEq features integrated as optional per-band/global fields. UltraEqWrapper instantiates ProEq with Ultra features enabled by default.

---

## Visual Design

```
COLOR PALETTE — PRO AUDIO DARK:

Backgrounds:
├── #0a0a0c  (deepest)
├── #121216  (deep)
├── #1a1a20  (mid)
└── #242430  (surface)

Accents:
├── #4a9eff  (blue — focus, selection)
├── #ff9040  (orange — active, EQ boost)
├── #40ff90  (green — positive, OK)
├── #ff4060  (red — clip, error)
└── #40c8ff  (cyan — spectrum, EQ cut)

Metering gradient:
#40c8ff → #40ff90 → #ffff40 → #ff9040 → #ff4040
```

---

## Workflow

### Pre izmene

1. Grep za sve instance
2. Mapiraj dependencies
3. Napravi listu fajlova

### Tokom izmene

4. Promeni SVE odjednom
5. Ne patch po patch

### Posle izmene

6. `cargo build`
7. `cargo test`
8. `cargo clippy`

---
