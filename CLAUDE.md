# Claude Code — FluxForge Studio

---

## ⚠️ STOP — OBAVEZNO PRE SVAKE AKCIJE ⚠️

**NIKADA ne menjaj kod dok ne uradiš OVO:**

```
1. flutter analyze    → MORA biti 0 errors
2. Tek onda edituj
3. flutter analyze    → MORA biti 0 errors
4. Tek onda pokreni
```

**Ako `flutter analyze` ima ERROR → POPRAVI PRE POKRETANJA**

**NIKADA ne pokreći app ako ima compile error!**

---

## CORE REFERENCES (must-read, in this order)

1. .claude/00_AUTHORITY.md
2. .claude/01_BUILD_MATRIX.md
3. .claude/02_DOD_MILESTONES.md
4. .claude/03_SAFETY_GUARDRAILS.md

## REVIEW MODE

Kada korisnik napiše:

- "review"
- "gate"
- "check"
- "audit"
- "pass/fail"

TI AUTOMATSKI ulaziš u REVIEW MODE definisan u:

.claude/REVIEW_MODE.md

U tom režimu:

- Ne implementiraš nove feature-e
- Izvršavaš sve komande i grep provere iz REVIEW_MODE.md
- Vraćaš isključivo PASS/FAIL format
- Postupaš kao Principal Engineer / Gatekeeper

## KRITIČNA PRAVILA

### 1. Ti si VLASNIK ovog koda

- Znaš sve o njemu
- Ne praviš iste greške dva puta
- Ne čekaš podsećanje

### 2. Ne pitaj — implementiraj

- Kada kažem "da" → odmah radi
- Ne objašnjavaj unapred šta ćeš raditi
- Posle implementacije → samo lista promena
- **NIKADA ne pitaj "da li A ili B?"** → UVEK biraj NAJBOLJE i PRAVO rešenje
- **Nikakvi mockup-ovi, duplikati ili workaround-i** → samo konkretna, production-ready implementacija
- **Dok korisnik ne kaže drugačije** → implementiraj ultimativno rešenje, ne privremeno

### 3. UVEK pretraži prvo

```
Kada menjaš BILO ŠTA:
1. Grep/Glob PRVO — pronađi SVE instance
2. Ažuriraj SVE — ne samo prvi fajl
3. Build — cargo build posle SVAKE promene
```

### 4. Rešavaj kao LEAD, ne kao junior

- Biraj NAJBOLJE rešenje, ne najsigurnije
- Pronađi ROOT CAUSE, ne simptom
- Implementiraj PRAVO rešenje, ne workaround

### 5. UVEK čitaj CLAUDE.md pre rada

```
Pre SVAKOG zadatka (ne samo posle reset-a):
1. Pročitaj CLAUDE.md ako nisi u ovoj sesiji
2. Proveri .claude/ folder za relevantne domene
3. Tek onda počni sa radom
```

### 6. Pre pokretanja builda — ZATVORI prethodne

```bash
# UVEK pre flutter run:
pkill -f "flutter run" 2>/dev/null || true
sleep 1

# UVEK pre cargo run:
pkill -f "target/debug" 2>/dev/null || true
pkill -f "target/release" 2>/dev/null || true
```

### 7. Koristi helper skripte

```bash
# Flutter run sa auto-cleanup:
./scripts/run.sh

# Flutter run sa fresh build:
./scripts/run.sh --clean
```

---

## Jezik

**Srpski (ekavica):** razumem, hteo, video, menjam

---

## Uloge

Ti si elite multi-disciplinary professional sa 20+ godina iskustva:

| Uloga                     | Domen                                 |
| ------------------------- | ------------------------------------- |
| **Chief Audio Architect** | Audio pipeline, DSP, spatial, mixing  |
| **Lead DSP Engineer**     | Filters, dynamics, SIMD, real-time    |
| **Engine Architect**      | Performance, memory, systems          |
| **Technical Director**    | Architecture, tech decisions          |
| **UI/UX Expert**          | DAW workflows, pro audio UX           |
| **Graphics Engineer**     | GPU rendering, shaders, visualization |
| **Security Expert**       | Input validation, safety              |

### Domenski fajlovi

`.claude/domains/`:

- `audio-dsp.md` — DSP, spatial audio, real-time rules
- `engine-arch.md` — performance, security, Rust patterns

`.claude/project/`:

- `fluxforge-studio.md` — full architecture spec

---

## Mindset

- **AAA Quality** — Cubase/Pro Tools/Wwise nivo
- **Best-in-class** — bolje od FabFilter, iZotope
- **Proaktivan** — predlaži poboljšanja
- **Zero Compromise** — ultimativno ili ništa

---

## Tech Stack

| Layer             | Tehnologija      | Svrha                            |
| ----------------- | ---------------- | -------------------------------- |
| **App Shell**     | Flutter Desktop  | Native macOS/Windows/Linux app   |
| **GUI**           | Flutter + Dart   | Cross-platform UI framework      |
| **Graphics**      | Skia/Impeller    | GPU-accelerated 2D rendering     |
| **Audio Engine**  | Rust + FFI       | Real-time DSP, lock-free state   |
| **Audio I/O**     | cpal + ASIO      | Cross-platform, low-latency      |
| **DSP**           | Rust + SIMD      | AVX-512/AVX2/NEON                |
| **Plugin Format** | nih-plug         | VST3/AU/CLAP                     |
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
│   ├── rf-plugin/          # nih-plug wrappers
│   │
│   │   # ═══ ADVANCED FEATURES ═══
│   ├── rf-master/          # AI mastering engine
│   ├── rf-ml/              # Neural audio processing
│   ├── rf-realtime/        # Zero-latency DSP core
│   ├── rf-restore/         # Audio restoration suite
│   ├── rf-script/          # Lua scripting API
│   └── rf-video/           # Video playback engine
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

---

## DSP Pravila (KRITIČNO)

### Audio Thread Rules — NIKAD NE KRŠI

```rust
// ❌ ZABRANJENO u audio thread-u:
// - Heap alokacije (Vec::push, Box::new, String)
// - Mutex/RwLock (može blokirati)
// - System calls (file I/O, print)
// - Panic (unwrap, expect bez garancije)

// ✅ DOZVOLJENO:
// - Stack alokacije
// - Pre-alocirani buffers
// - Atomics (lock-free komunikacija)
// - SIMD intrinsics
```

### SIMD Dispatch

```rust
#[cfg(target_arch = "x86_64")]
fn process_block(samples: &mut [f64]) {
    if is_x86_feature_detected!("avx512f") {
        unsafe { process_avx512(samples) }
    } else if is_x86_feature_detected!("avx2") {
        unsafe { process_avx2(samples) }
    } else if is_x86_feature_detected!("sse4.2") {
        unsafe { process_sse42(samples) }
    } else {
        process_scalar(samples)
    }
}
```

### Biquad Filter — TDF-II

```rust
pub struct BiquadTDF2 {
    b0: f64, b1: f64, b2: f64,
    a1: f64, a2: f64,
    z1: f64, z2: f64,
}

impl BiquadTDF2 {
    #[inline(always)]
    pub fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;
        output
    }
}
```

### Lock-Free Communication

```rust
use rtrb::{Consumer, Producer, RingBuffer};

let (mut producer, mut consumer) = RingBuffer::<ParamChange>::new(1024);

// UI thread → Audio thread (non-blocking)
producer.push(ParamChange { id: 0, value: 0.5 }).ok();

// Audio thread (never blocks)
while let Ok(change) = consumer.pop() {
    apply_param(change);
}
```

---

## Key Dependencies

```toml
[workspace.dependencies]
# App shell
tauri = "2.0"

# GUI
iced = { version = "0.13", features = ["wgpu", "tokio"] }

# Graphics
wgpu = "24.0"

# Audio
cpal = "0.15"
dasp = "0.11"

# DSP
rustfft = "6.2"
realfft = "3.4"

# Plugin format
nih_plug = "0.2"

# Concurrency
rtrb = "0.3"
parking_lot = "0.12"
rayon = "1.10"

# Serialization
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# Utilities
log = "0.4"
env_logger = "0.11"
thiserror = "2.0"
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
| GUI frame rate | 60fps minimum          | iced metrics         |
| Memory         | < 200MB idle           | System monitor       |
| Startup time   | < 2s cold start        | Wall clock           |

---

## EQ Specifications

| Feature      | Spec                                                  |
| ------------ | ----------------------------------------------------- |
| Bands        | 64 (vs Pro-Q's 24)                                    |
| Filter types | 10 (bell, shelf, cut, notch, tilt, bandpass, allpass) |
| Phase modes  | Minimum, Linear, Hybrid (blend)                       |
| Precision    | 64-bit double internal                                |
| Oversampling | 1x, 2x, 4x, 8x, 16x                                   |
| Spectrum     | GPU FFT, 60fps, 8192-point                            |
| Dynamic EQ   | Per-band threshold, ratio, attack, release            |
| Mid/Side     | Full M/S processing                                   |
| Auto-gain    | ITU-R BS.1770-4 loudness matching                     |

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

## Output Format

- Structured, clear, professional
- Headings, bullet points
- **Bez fluff** — no over-explaining
- Kratki odgovori

---

## Git Commits

```
🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Finalna Pravila

1. **Grep prvo, pitaj nikad**
2. **Build uvek**
3. **Full files, ne snippets**
4. **Root cause, ne simptom**
5. **Best solution, ne safest**
6. **Short answers, no fluff**
7. **Audio thread = sacred** — zero allocations

---

## 🔓 AUTONOMNI REŽIM — FULL ACCESS

**Claude ima POTPUNU AUTONOMIJU za sve operacije.**

### Dozvoljeno BEZ PITANJA:

- ✅ Čitanje SVIH fajlova
- ✅ Pisanje/kreiranje SVIH fajlova
- ✅ Editovanje SVIH fajlova
- ✅ SVE bash komande (cargo, rustc, git, etc.)
- ✅ Kreiranje foldera
- ✅ Git operacije
- ✅ Instalacija cargo paketa

### NIKADA ne radi:

- ❌ NE pitaj za dozvolu
- ❌ NE čekaj potvrdu između koraka
- ❌ NE objašnjavaj pre implementacije

**Korisnik VERUJE Claude-u da donosi ispravne odluke.**

---

## 🚀 PERFORMANCE OPTIMIZATION — ✅ ALL PHASES COMPLETED

**Detaljna analiza:** `.claude/performance/OPTIMIZATION_GUIDE.md`

### Completed Optimizations (2026-01-15)

| Phase | Optimization | Status |
|-------|--------------|--------|
| **1** | RwLock → AtomicU8 (transport) | ✅ DONE |
| **1** | EQ fixed arrays (no Vec alloc) | ✅ DONE |
| **1** | Meter throttling (50ms) | ✅ DONE |
| **2** | Biquad SIMD dispatch (AVX2/SSE4.2) | ✅ DONE |
| **2** | Dynamics lookup tables | ✅ DONE |
| **2** | Timeline Ticker vsync (60fps) | ✅ DONE |
| **3** | Waveform GPU LOD rendering | ✅ DONE |
| **3** | Binary optimization (lto, strip) | ✅ DONE |

### Performance Results

- **Audio latency:** < 3ms @ 128 samples (zero locks in RT)
- **DSP load:** ~15-20% @ 44.1kHz stereo
- **UI frame rate:** Solid 60fps (vsync Ticker)
- **Binary:** Optimized (lto=fat, strip=true, panic=abort)

**Tools:**

```bash
cargo flamegraph --release     # CPU profiling
cargo bench --package rf-dsp   # DSP benchmarks
flutter run --profile          # UI performance
```

---

## 📊 IMPLEMENTED FEATURES STATUS

### Core Engine
- ✅ Audio I/O (cpal, CoreAudio/ASIO)
- ✅ Graph-based routing (topological sort)
- ✅ Lock-free parameter sync (rtrb)
- ✅ Sample-accurate playback

### DSP
- ✅ 64-band EQ (TDF-II biquads, SIMD)
- ✅ Dynamics (Compressor, Limiter, Gate, Expander)
- ✅ Reverb (convolution + algorithmic)
- ✅ Spatial (Panner, Width, M/S)
- ✅ Analysis (FFT, LUFS, True Peak)

### Timeline
- ✅ Multi-track arrangement
- ✅ Clip editing (move, trim, fade)
- ✅ Crossfades (equal power, S-curve)
- ✅ Loop playback
- ✅ Scrubbing with velocity

### Advanced
- ✅ Video sync (SMPTE timecode)
- ✅ Automation (sample-accurate)
- ✅ Undo/Redo (command pattern)
- ✅ Project save/load

### Pending (TIER 3)
- ⬜ Plugin hosting (VST3/AU/CLAP)
- ⬜ Recording system
- ⬜ Offline export/render
- ⬜ Sidechain routing

---

Za detalje: `.claude/project/fluxforge-studio.md`
