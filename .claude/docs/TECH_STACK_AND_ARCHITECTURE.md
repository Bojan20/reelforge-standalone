## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **App Shell** | Flutter Desktop | Native macOS/Windows/Linux |
| **GUI** | Flutter + Dart | Cross-platform UI |
| **Graphics** | Skia/Impeller | GPU-accelerated 2D |
| **Audio Engine** | Rust + FFI | Real-time DSP, lock-free |
| **Audio I/O** | cpal + ASIO | Low-latency, cross-platform |
| **DSP** | Rust + SIMD | AVX-512/AVX2/NEON |
| **Plugin Hosting** | vst3 + rack + clap + lv2 | VST3/AU/CLAP/LV2 (production), MIDI instruments, multi-output (64ch) |
| **Serialization** | serde | JSON/Binary projects |

**Languages:** Dart 45%, Rust 54%, WGSL 1%

---

## 7-Layer Architecture

| Layer | Name | Key Components |
|-------|------|----------------|
| 7 | Application Shell | Native app, file dialogs, menus, project save/load, plugin hosting |
| 6 | GUI Framework | Skia/Impeller, custom widgets (knobs/faders/meters/waveforms), Provider state, 120fps |
| 5 | FFI Bridge | `native_ffi.dart` (6000+ LOC), lock-free param sync, real-time metering |
| 4 | State Management | Undo/redo (command pattern), A/B comparison, preset management, automation |
| 3 | Audio Engine (rf-engine) | Dual-path (real-time + guard), graph routing, 6 buses + master, insert/send FX, sidechain |
| 2 | DSP Processors (rf-dsp) | EQ (64-band TDF-II biquads, linear/hybrid phase), dynamics, spatial, time, analysis (FFT/LUFS/TruePeak). ALL SIMD optimized |
| 1 | Audio I/O (cpal) | ASIO (Win), CoreAudio (Mac), JACK/PipeWire (Linux). 44.1–384kHz, 32–4096 samples |

---

## Workspace Structure

```
fluxforge-studio/
├── Cargo.toml, rust-toolchain.toml, .cargo/config.toml
├── crates/
│   ├── rf-core/        # Shared types, traits
│   ├── rf-dsp/         # DSP processors (SIMD)
│   ├── rf-audio/       # Audio I/O (cpal)
│   ├── rf-engine/      # Audio graph, routing, FFI
│   ├── rf-bridge/      # Flutter-Rust FFI bridge
│   ├── rf-state/       # Undo/redo, presets
│   ├── rf-file/        # Audio file I/O
│   ├── rf-viz/         # wgpu visualizations (future)
│   ├── rf-plugin/      # VST3/AU/CLAP hosting
│   ├── rf-master/      # AI mastering engine
│   ├── rf-ml/          # Neural audio (ONNX Runtime)
│   ├── rf-realtime/    # Zero-latency DSP core
│   ├── rf-restore/     # Audio restoration suite
│   ├── rf-script/      # Lua scripting API
│   ├── rf-video/       # Video playback engine
│   ├── rf-fuzz/        # FFI fuzzing framework
│   ├── rf-audio-diff/  # Spectral audio comparison
│   ├── rf-bench/       # Performance benchmarks
│   ├── rf-coverage/    # Code coverage reporting
│   ├── rf-release/     # Release automation
│   └── rf-offline/     # Batch audio processing
├── flutter_ui/
│   └── lib/ (models/, providers/, screens/, widgets/, src/rust/)
├── shaders/            # WGSL shaders
└── assets/             # Fonts, icons
```

---

## Advanced Crates

| Crate | LOC | Purpose |
|-------|-----|---------|
| **rf-master** | 4,921 | AI mastering — genre analysis, LUFS targeting, spectral balance, multiband dynamics, stereo enhancement, true peak limiting, reference matching. Presets: CD, Streaming, Apple Music, Broadcast, Club, Vinyl, Podcast, Film |
| **rf-ml** | 1,541 | Neural audio — DeepFilterNet3 denoising (~10ms), HTDemucs v4 stem separation, speech enhancement (~5ms), EQ matching, genre classification. Backends: CUDA/TensorRT, CoreML, tract |
| **rf-realtime** | 5,253 | MassCore++ inspired — triple-buffer lock-free state, SIMD runtime dispatch, zero-copy ring buffers, deterministic timing. Target: <1ms at 128 samples |
| **rf-restore** | 550 | Audio repair — declip, dehum (50/60Hz+harmonics), declick, spectral denoise, dereverb. Chainable with auto latency compensation |
| **rf-script** | 978 | Lua scripting — macros, automation, analysis scripts, external tool control. Full API access |
| **rf-video** | 2,022 | Video playback — H.264/H.265/ProRes/DNxHD (FFmpeg), frame-accurate seeking, sample-accurate A/V sync, SMPTE timecode, EDL/AAF import |
| **rf-ale** | 4,500 | Adaptive Layer Engine — 18+ signals, context system, 16 comparison operators, 7 stability mechanisms, 6 sync modes, 10 fade curves |
| **rf-wasm** | ~400 | WebAssembly port — Web Audio API, 32 voices, 8 buses, RTPC, state groups. Release: ~45KB gzipped |

---

## M4: QA & Testing Infrastructure

| Crate | Purpose |
|-------|---------|
| **rf-fuzz** | Reproducible FFI fuzzing — ChaCha8Rng, edge cases (NaN/Inf/denormals), panic catching |
| **rf-audio-diff** | Spectral comparison — FFT-based, golden files, quality gates (LUFS/TruePeak/DR), bit-exact validation |
| **rf-bench** | Criterion benchmarks — DSP, SIMD vs scalar, buffer throughput |
| **rf-coverage** | llvm-cov parsing — configurable thresholds, HTML/MD/JSON/Badge reports, trend tracking |
| **rf-release** | SemVer 2.0 — conventional commit changelog, multi-platform packaging, release manifest |

### rf-offline — Batch Audio Processing (~2900 LOC)

| Feature | Details |
|---------|---------|
| **Import** | WAV, AIFF, FLAC, ALAC, MP3, OGG/Vorbis, AAC, M4A (all via Symphonia) |
| **Export Native** | WAV (16/24/32f), AIFF, FLAC, MP3, OGG, Opus |
| **Export FFmpeg** | AAC only (requires FFmpeg in PATH) |
| **Metering** | EBU R128 LUFS (integrated/short-term/momentary), True Peak (4x oversampled) |
| **Normalization** | LUFS target (-14/-16/-23), Peak target, Dynamic range |
| **Pipeline** | Job queue with async processing, progress callbacks |

**FFI:** `offline_pipeline_create/set_format/process_file/destroy`, `offline_get_audio_info`
