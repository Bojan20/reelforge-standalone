## Tech Stack

| Layer             | Tehnologija      | Svrha                            |
| ----------------- | ---------------- | -------------------------------- |
| **App Shell**     | Flutter Desktop  | Native macOS/Windows/Linux app   |
| **GUI**           | Flutter + Dart   | Cross-platform UI framework      |
| **Graphics**      | Skia/Impeller    | GPU-accelerated 2D rendering     |
| **Audio Engine**  | Rust + FFI       | Real-time DSP, lock-free state   |
| **Audio I/O**     | cpal + ASIO      | Cross-platform, low-latency      |
| **DSP**           | Rust + SIMD      | AVX-512/AVX2/NEON                |
| **Plugin Hosting**| vst3 + rack      | VST3/AU/CLAP scanner & hosting   |
| **Serialization** | serde            | JSON/Binary projects             |

### Jezici

```
Dart:   45%  — Flutter UI, state management
Rust:   54%  — DSP, audio engine, FFI bridge
WGSL:    1%  — GPU shaders (rf-viz, future)
```

---

## 7-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 7: Application Shell (Flutter Desktop)                     │
│ ├── Native macOS/Windows/Linux app                               │
│ ├── File dialogs, menus (platform native)                       │
│ ├── Project save/load/autosave                                  │
│ └── Plugin hosting (VST3/AU/CLAP scanner)                       │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 6: GUI Framework (Flutter + Dart)                          │
│ ├── Skia/Impeller backend — GPU accelerated                     │
│ ├── Custom widgets: knobs, faders, meters, waveforms            │
│ ├── 120fps capable (Impeller on supported platforms)            │
│ └── Provider state management                                    │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 5: FFI Bridge (dart:ffi → Rust)                            │
│ ├── native_ffi.dart — 6000+ LOC bindings                        │
│ ├── Lock-free parameter sync                                     │
│ ├── Real-time metering data                                      │
│ └── DSP processor control                                        │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 4: State Management (Dart Providers)                       │
│ ├── Undo/Redo (command pattern)                                 │
│ ├── A/B comparison                                               │
│ ├── Preset management (JSON schema)                             │
│ ├── Parameter automation (sample-accurate)                      │
│ └── Project serialization (versioned)                           │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 3: Audio Engine (Rust: rf-engine)                          │
│ ├── Dual-path: Real-time + Guard (async lookahead)              │
│ ├── Graph-based routing                                          │
│ ├── 6 buses + master                                             │
│ ├── Insert/Send effects                                          │
│ └── Sidechain support                                            │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 2: DSP Processors (Rust: rf-dsp)                           │
│ ├── EQ: 64-band, TDF-II biquads, linear/hybrid phase            │
│ ├── Dynamics: Compressor, Limiter, Gate, Expander               │
│ ├── Spatial: Panner, Width, M/S                                 │
│ ├── Time: Delay, Reverb (convolution + algorithmic)             │
│ ├── Analysis: FFT, LUFS, True Peak, Correlation                 │
│ └── ALL SIMD optimized (AVX-512/AVX2/SSE4.2/NEON)               │
├─────────────────────────────────────────────────────────────────┤
│ LAYER 1: Audio I/O (Rust: cpal)                                  │
│ ├── ASIO (Windows) — via asio-sys                               │
│ ├── CoreAudio (macOS) — native                                  │
│ ├── JACK/PipeWire (Linux)                                       │
│ ├── Sample rates: 44.1kHz → 384kHz                              │
│ └── Buffer sizes: 32 → 4096 samples                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Workspace Structure

```
fluxforge-studio/
├── Cargo.toml              # Workspace root
├── rust-toolchain.toml     # Nightly for SIMD
├── .cargo/config.toml      # Build flags, target-cpu
│
├── crates/
│   ├── rf-core/            # Shared types, traits
│   ├── rf-dsp/             # DSP processors (SIMD)
│   ├── rf-audio/           # Audio I/O (cpal)
│   ├── rf-engine/          # Audio graph, routing, FFI
│   ├── rf-bridge/          # Flutter-Rust FFI bridge
│   ├── rf-state/           # Undo/redo, presets
│   ├── rf-file/            # Audio file I/O
│   ├── rf-viz/             # wgpu visualizations (future)
│   ├── rf-plugin/          # VST3/AU/CLAP hosting (vst3, rack)
│   │
│   │   # ═══ ADVANCED FEATURES ═══
│   ├── rf-master/          # AI mastering engine
│   ├── rf-ml/              # Neural audio processing
│   ├── rf-realtime/        # Zero-latency DSP core
│   ├── rf-restore/         # Audio restoration suite
│   ├── rf-script/          # Lua scripting API
│   ├── rf-video/           # Video playback engine
│   │
│   │   # ═══ QA & TESTING (M4) ═══
│   ├── rf-fuzz/            # FFI fuzzing framework
│   ├── rf-audio-diff/      # Spectral audio comparison
│   ├── rf-bench/           # Performance benchmarks
│   ├── rf-coverage/        # Code coverage reporting
│   ├── rf-release/         # Release automation
│   └── rf-offline/         # Batch audio processing
│
├── flutter_ui/             # Flutter Desktop GUI
│   ├── lib/
│   │   ├── models/         # Data models
│   │   ├── providers/      # State management
│   │   ├── screens/        # Main screens
│   │   ├── widgets/        # Custom widgets
│   │   │   ├── common/     # Knobs, faders, meters
│   │   │   ├── dsp/        # DSP processor panels
│   │   │   ├── mixer/      # Mixer components
│   │   │   └── timeline/   # Timeline/arrangement
│   │   └── src/rust/       # FFI bindings (native_ffi.dart)
│   └── macos/windows/linux # Platform runners
│
├── shaders/                # WGSL shaders (rf-viz)
└── assets/                 # Fonts, icons
```

---

## Advanced Crates (Detailed)

### rf-master — AI Mastering Engine (4,921 LOC)

Intelligent mastering with genre-aware processing:

| Feature | Description |
|---------|-------------|
| **Genre Analysis** | Auto-detect genre for context-aware processing |
| **Loudness Targeting** | LUFS-based normalization (Streaming: -14, Broadcast: -23, Club: -8) |
| **Spectral Balance** | EQ matching and tonal correction |
| **Dynamic Control** | Adaptive multiband dynamics with genre profiles |
| **Stereo Enhancement** | Width optimization, mono compatibility |
| **True Peak Limiting** | ISP-safe limiting with 8x oversampling |
| **Reference Matching** | Match spectral/dynamic profile of reference tracks |

**Presets:** CD/Lossless, Streaming, Apple Music, Broadcast, Club, Vinyl, Podcast, Film

### rf-ml — Neural Audio Processing (1,541 LOC)

State-of-the-art ML/AI audio processing via ONNX Runtime:

| Module | Model | Latency | Use Case |
|--------|-------|---------|----------|
| **Denoising** | DeepFilterNet3, FRCRN | ~10ms | Background noise removal |
| **Stem Separation** | HTDemucs v4 | Offline | Vocals/drums/bass/other split |
| **Speech Enhancement** | aTENNuate SSM | ~5ms | Voice clarity |
| **EQ Matching** | Spectral Transfer | — | Reference matching |
| **Genre Classification** | Custom CNN | — | Auto-genre detection |

**Backends:** CUDA/TensorRT (NVIDIA), CoreML (Apple Silicon), tract (CPU/WASM fallback)

### rf-realtime — Zero-Latency DSP Core (5,253 LOC)

MassCore++ inspired ultra-low-latency processing:

| Feature | Description |
|---------|-------------|
| **Triple-Buffer State** | Lock-free UI↔Audio communication |
| **SIMD Dispatch** | Runtime AVX-512/AVX2/SSE4.2/NEON selection |
| **Zero-Copy Processing** | Pre-allocated ring buffers |
| **Deterministic Timing** | No allocations in audio callback |
| **Guard Path** | Async lookahead for complex processing |

**Target:** < 1ms internal latency at 128 samples

### rf-restore — Audio Restoration Suite (550 LOC)

Professional audio repair and restoration:

| Module | Function |
|--------|----------|
| **Declip** | Hard/soft clipping reconstruction (spline interpolation) |
| **Dehum** | Multi-harmonic hum removal (50/60 Hz + harmonics) |
| **Declick** | Impulsive noise detection, vinyl crackle removal |
| **Denoise** | Spectral subtraction with psychoacoustic weighting |
| **Dereverb** | Reverb suppression, early reflections removal |

**Pipeline:** Chainable modules with automatic latency compensation

### rf-script — Lua Scripting API (978 LOC)

Automation and extensibility via embedded Lua:

| Capability | Examples |
|------------|----------|
| **Macros** | Batch rename, auto-fade, normalize selected |
| **Automation** | Custom LFOs, randomization, algorithmic edits |
| **Analysis** | Custom meters, spectral analysis scripts |
| **Integration** | External tool control, OSC/MIDI scripting |

**API:** Full access to tracks, clips, parameters, transport

### rf-video — Video Playback Engine (2,022 LOC)

Professional video for post-production:

| Feature | Description |
|---------|-------------|
| **Codecs** | H.264, H.265, ProRes, DNxHD (via FFmpeg) |
| **Seeking** | Frame-accurate with keyframe indexing |
| **Sync** | Sample-accurate A/V sync via timecode |
| **Thumbnails** | Strip generation for timeline preview |
| **Timecode** | SMPTE formats (23.976, 24, 25, 29.97df, 30) |
| **Import** | EDL/AAF support |

**Frame Cache:** LRU cache with background preloading

### rf-ale — Adaptive Layer Engine (4,500 LOC) ✅ NEW

Data-driven, context-aware, metric-reactive music system for dynamic audio layering.

| Component | Description |
|-----------|-------------|
| **Signal System** | 18+ built-in signals (winTier, momentum, etc.), normalization modes (linear, sigmoid, asymptotic) |
| **Context System** | Game chapters (BASE, FREESPINS, HOLDWIN...) with layers, entry/exit policies, narrative arcs |
| **Rule System** | 16 comparison operators, compound conditions (AND/OR/NOT/HELD_FOR), 6 action types |
| **Stability System** | 7 mechanisms: cooldown, hold, hysteresis, level_inertia, decay, momentum_buffer, prediction |
| **Transition System** | 6 sync modes (immediate, beat, bar, phrase), 10 fade curves, crossfade overlap |
| **Profile System** | JSON serialization, version migration, validation |

**FFI:** `crates/rf-bridge/src/ale_ffi.rs` (~780 LOC)
**Dart Provider:** `flutter_ui/lib/providers/ale_provider.dart` (~745 LOC)
**Documentation:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md` (~2350 LOC)

### rf-wasm — WASM Port (2026-01-22) ✅

WebAssembly port za web browser runtime.

| Feature | Description |
|---------|-------------|
| **Web Audio API** | Full AudioContext, GainNode, StereoPannerNode integration |
| **Event System** | Howler-style event playback with layering |
| **Voice Pooling** | 32 voices, stealing modes (Oldest, Quietest, LowestPriority) |
| **Bus Routing** | 8 buses (Master, SFX, Music, Voice, Ambience, UI, Reels, Wins) |
| **RTPC** | Real-time parameter control with slew rate |
| **State System** | State groups with transition support |

**Location:** `crates/rf-wasm/`

| File | Description |
|------|-------------|
| `Cargo.toml` | wasm-bindgen, web-sys features for Web Audio |
| `src/lib.rs` | FluxForgeAudio class, ~400 LOC |
| `js/fluxforge-audio.ts` | TypeScript wrapper |
| `README.md` | Usage documentation |

**Binary Size:**
| Build | Raw | Gzipped |
|-------|-----|---------|
| Debug | ~200KB | ~80KB |
| Release | ~120KB | ~45KB |
| Release + wee_alloc | ~100KB | ~38KB |

**Build:** `wasm-pack build --target web --release`

---

## M4: QA & Testing Infrastructure

### rf-fuzz — FFI Fuzzing Framework

Reproducible fuzzing for FFI boundary testing.

| Feature | Description |
|---------|-------------|
| **Random Input** | ChaCha8Rng-based reproducible generation |
| **Edge Cases** | NaN, Inf, denormals, boundary values |
| **Panic Catching** | Catch and report panics without crashing |
| **Property Testing** | Output validation with custom validators |

**Usage:**
```rust
let result = quick_fuzz(1000, |bytes| unsafe { ffi_function(bytes.as_ptr()) });
assert!(result.passed);
```

### rf-audio-diff — Spectral Audio Comparison

FFT-based audio comparison for regression testing.

| Feature | Description |
|---------|-------------|
| **Spectral Analysis** | FFT-based frequency domain comparison |
| **Golden Files** | Reference audio storage and comparison |
| **Quality Gates** | LUFS, true peak, dynamic range checks |
| **Determinism** | Bit-exact reproducibility validation |

**Usage:**
```rust
let result = quick_compare("reference.wav", "test.wav")?;
assert!(result.is_pass());
```

### rf-bench — Performance Benchmarks

Criterion-based benchmarking for DSP and SIMD.

| Benchmark | Description |
|-----------|-------------|
| **DSP** | Filter, dynamics, gain processing |
| **SIMD** | AVX2/SSE4.2 vs scalar comparisons |
| **Buffer** | Memory throughput, interleaving |

**Usage:**
```bash
cargo bench -p rf-bench -- dsp
cargo bench -p rf-bench -- --save-baseline main
```

### rf-coverage — Code Coverage Reporting

llvm-cov parsing and threshold enforcement.

| Feature | Description |
|---------|-------------|
| **Parser** | llvm-cov JSON format support |
| **Thresholds** | Configurable pass/fail criteria |
| **Reports** | HTML, Markdown, JSON, Badge formats |
| **Trends** | Historical coverage tracking |

**Usage:**
```bash
cargo llvm-cov --json --output-path coverage.json
cargo run -p rf-coverage -- check coverage.json --min-line 80
```

### rf-release — Release Automation

Semantic versioning and release management.

| Feature | Description |
|---------|-------------|
| **Versioning** | SemVer 2.0 with prerelease support |
| **Changelog** | Conventional commit parsing |
| **Packaging** | Multi-platform artifact generation |
| **Manifest** | Release manifest (JSON/Markdown) |

**Usage:**
```rust
let mut manager = ReleaseManager::new(config);
manager.bump(BumpType::Minor);
let plan = manager.prepare()?;
```

### rf-offline — Batch Audio Processing (~2900 LOC)

High-performance offline DSP pipeline with professional metering and format conversion.

**Location:** `crates/rf-offline/`

| Module | Description |
|--------|-------------|
| **decoder.rs** | Universal audio decoder (WAV, FLAC, MP3, OGG, AAC, AIFF, ALAC, M4A via symphonia) |
| **encoder.rs** | Multi-format encoder — Native: WAV, AIFF, FLAC, MP3, OGG, Opus — FFmpeg: AAC only |
| **formats.rs** | Output format definitions and configurations |
| **normalize.rs** | EBU R128 LUFS metering with K-weighting, True Peak detection (4x oversampling) |
| **pipeline.rs** | Job-based processing pipeline with progress callbacks |
| **time_stretch.rs** | Phase vocoder time stretching |

**Audio Format Support:** `.claude/docs/AUDIO_FORMAT_SUPPORT.md`

| Category | Formats | Notes |
|----------|---------|-------|
| **Import (Decode)** | WAV, AIFF, FLAC, ALAC, MP3, OGG/Vorbis, AAC, M4A | All via Symphonia (pure Rust) |
| **Export Native** | WAV (16/24/32f), AIFF (8/16/24/32), FLAC (16/24), MP3 (128-320kbps, VBR), OGG (Q-1 to Q10), Opus (6-510kbps) | No FFmpeg required* |
| **Export FFmpeg** | AAC (128-320kbps) | Requires FFmpeg in PATH |

*MP3 requires libmp3lame, OGG requires libvorbis, Opus requires libopus (via pkg-config or bundled)

**Key Features:**
| Feature | Description |
|---------|-------------|
| **EBU R128 LUFS** | Integrated, short-term, momentary loudness with K-weighting filters |
| **True Peak** | 4x oversampled ISP detection for streaming compliance |
| **Format Conversion** | Decode any (8 formats) → process → encode to 15 target formats |
| **Normalization Modes** | LUFS target (-14/-16/-23), Peak target, Dynamic range |
| **Batch Processing** | Job queue with async processing |

**FFI Functions** (`crates/rf-bridge/src/offline_ffi.rs`):
```rust
offline_pipeline_create() -> i32
offline_pipeline_set_format(handle, format_id)
offline_process_file(handle, input_path, output_path) -> i32
offline_pipeline_destroy(handle)
offline_get_audio_info(path) -> JSON
```

**Usage:**
```rust
let job = OfflineJob::new()
    .input("source.wav")
    .output("output.wav")
    .normalize(NormalizationMode::Lufs { target: -14.0 })
    .build();
processor.process(job).await?;
```

**Usage:**
```rust
let job = OfflineJob::new()
    .input("source.wav")
    .output("output.wav")
    .normalize(NormalizationMode::Lufs { target: -14.0 })
    .build();
processor.process(job).await?;
```

**Documentation:** `.claude/docs/QA_TOOLS_GUIDE.md`, `.claude/architecture/QA_ARCHITECTURE.md`

---

