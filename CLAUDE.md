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

## 🔴 KRITIČNO — FULL BUILD PROCEDURA 🔴

**PRE SVAKOG POKRETANJA APLIKACIJE — OBAVEZNO URADI SVE KORAKE:**

### Kompletna Build Sekvenca (COPY-PASTE READY)

```bash
# ══════════════════════════════════════════════════════════════════════════════
# KORAK 1: KILL PRETHODNE PROCESE
# ══════════════════════════════════════════════════════════════════════════════
pkill -f "FluxForge" 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true
sleep 1

# ══════════════════════════════════════════════════════════════════════════════
# KORAK 2: BUILD RUST BIBLIOTEKE
# ══════════════════════════════════════════════════════════════════════════════
cd "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio"
cargo build --release

# ══════════════════════════════════════════════════════════════════════════════
# KORAK 3: KOPIRAJ DYLIB-ove (KRITIČNO!)
# ══════════════════════════════════════════════════════════════════════════════
cp target/release/librf_bridge.dylib flutter_ui/macos/Frameworks/
cp target/release/librf_engine.dylib flutter_ui/macos/Frameworks/

# ══════════════════════════════════════════════════════════════════════════════
# KORAK 4: FLUTTER ANALYZE (MORA PROĆI)
# ══════════════════════════════════════════════════════════════════════════════
cd flutter_ui
flutter analyze
# MORA biti "No issues found!" — ako ima errors, POPRAVI PRE NASTAVKA

# ══════════════════════════════════════════════════════════════════════════════
# KORAK 5: BUILD MACOS APP (xcodebuild, NE flutter run)
# ══════════════════════════════════════════════════════════════════════════════
cd macos
find Pods -name '._*' -type f -delete 2>/dev/null || true
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FluxForge-macos build

# ══════════════════════════════════════════════════════════════════════════════
# KORAK 5.5: KOPIRAJ DYLIB-ove U APP BUNDLE (KRITIČNO! xcodebuild NE KOPIRA!)
# ══════════════════════════════════════════════════════════════════════════════
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_bridge.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_engine.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/

# ══════════════════════════════════════════════════════════════════════════════
# KORAK 6: POKRENI APLIKACIJU
# ══════════════════════════════════════════════════════════════════════════════
open ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app
```

### ZAŠTO JE OVO KRITIČNO

| Problem | Simptomi |
|---------|----------|
| Stari dylib-ovi u Frameworks | Audio import ne radi, waveform prazan, playback ne radi |
| Stari dylib-ovi u APP BUNDLE | "Lib: NOT LOADED" u debug overlay, FFI ne radi |
| flutter run na ext. disku | codesign greške, AppleDouble fajlovi |
| Preskočen flutter analyze | Runtime crash, null errors |

### VERIFIKACIJA (pre pokretanja)

```bash
# Proveri da su dylib datumi DANAS u SVE TRI LOKACIJE:
ls -la "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/target/release/"*.dylib
ls -la "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/"*.dylib
ls -la ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/*.dylib

# SVE TRI LOKACIJE MORAJU IMATI ISTI TIMESTAMP!
# Ako APP BUNDLE ima stariji datum → KOPIRAJ PONOVO (Korak 5.5)
```

### NIKADA NE RADI

- ❌ `flutter run` direktno (codesign fail na ext. disku)
- ❌ Pokretanje bez kopiranja dylib-ova
- ❌ Pokretanje bez `cargo build --release`
- ❌ Pokretanje ako `flutter analyze` ima errors

---

## ⚡ QUICK RUN COMMAND — "pokreni"

**Kada korisnik napiše "pokreni", "run", "start app" → ODMAH pokreni CELU SEKVENCU:**

```bash
# KILL existing
pkill -f "FluxForge" 2>/dev/null || true

# BUILD + COPY + RUN (sve u jednom)
cd "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos" && \
find Pods -name '._*' -type f -delete 2>/dev/null || true && \
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FluxForge-macos build && \
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_bridge.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/ && \
cp "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio/flutter_ui/macos/Frameworks/librf_engine.dylib" \
   ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app/Contents/Frameworks/ && \
open ~/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge\ Studio.app
```

**KRITIČNO:**
- UVEK koristi `~/Library/Developer/Xcode/DerivedData/` (HOME path)
- NIKADA `/Library/Developer/` (nema permisije)
- NIKADA `$HOME/FluxForge-DerivedData` (čudan path)

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

## DEBUGGING

**KORISNIK NEMA PRISTUP KONZOLI/LOGU.**

- NE koristi `debugPrint` ili `print` za debugging
- NE pitaj korisnika šta piše u logu
- Ako treba debug info, prikaži ga u samom UI-u (overlay, snackbar, ili debug panel)
- Ili: analiziraj kod logički bez oslanjanja na runtime log

---

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
- **NIKADA jednostavno rešenje — UVEK najbolje rešenje**

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

### 8. Eksterni disk (ExFAT/NTFS) build — OBAVEZNO

Projekat je na eksternom SSD-u (ExFAT). macOS kreira AppleDouble (`._*`) fajlove na non-HFS+ volumima koji uzrokuju codesign greške.

**REŠENJE: Koristi xcodebuild sa derived data na internom disku:**

```bash
# Koristi helper script:
./scripts/run-macos.sh

# Ili ručno:
cd flutter_ui/macos
find Pods -name '._*' -type f -delete 2>/dev/null || true
xcodebuild -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/FluxForge-macos" \
    build

# Zatim pokreni:
open "$HOME/Library/Developer/Xcode/DerivedData/FluxForge-macos/Build/Products/Debug/FluxForge Studio.app"
```

**NIKADA ne koristi `flutter run` direktno na eksternom disku** — koristiti samo xcodebuild pristup.

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

### FabFilter-Style Premium DSP Panels (2026-01-20) ✅

Professional DSP panel suite inspired by FabFilter's design language.

**Location:** `flutter_ui/lib/widgets/fabfilter/`

| Panel | Inspiration | Features | FFI |
|-------|-------------|----------|-----|
| `fabfilter_eq_panel.dart` | Pro-Q 3 | 64-band, spectrum, phase modes, dynamic EQ | ✅ |
| `fabfilter_compressor_panel.dart` | Pro-C 2 | Knee display, 14 styles, sidechain EQ | ✅ |
| `fabfilter_limiter_panel.dart` | Pro-L 2 | LUFS metering, 8 styles, true peak | ✅ |
| `fabfilter_reverb_panel.dart` | Pro-R | Decay display, pre-delay, brightness | ✅ |
| `fabfilter_gate_panel.dart` | Pro-G | Threshold viz, sidechain filter, range | ✅ |

**Shared Components:**
- `fabfilter_theme.dart` — Colors, gradients, text styles
- `fabfilter_knob.dart` — Pro knob with modulation ring, fine control
- `fabfilter_panel_base.dart` — A/B comparison, undo/redo, bypass
- `fabfilter_preset_browser.dart` — Categories, search, favorites

**Total:** ~6,400 LOC

**Lower Zone Integration:**
All panels accessible via Process group: `fabfilter-eq`, `fabfilter-comp`, `fabfilter-limiter`, `fabfilter-reverb`, `fabfilter-gate`

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

### Recording & Export
- ✅ Recording system (arm, punch-in/out, pre-roll, auto-arm)
- ✅ Offline export/render (WAV/FLAC/MP3, stems, normalize)
- ✅ Sidechain routing (external/internal, filter, M/S, monitor)

### Plugin & Workflow (TIER 4)
- ✅ Plugin hosting (VST3/AU/CLAP/LV2 scanner, PDC, ZeroCopyChain, cache validation)
- ✅ Take lanes / Comping (recording lanes, takes, comp regions)
- ✅ Tempo track / Time warp (tempo map, time signatures, grid)

### Unified Routing System (2026-01-20)
- ✅ Unified Routing Graph (dynamic channels, topological sort)
- ✅ FFI bindings (11 funkcija: create/delete/output/sends/volume/pan/mute/solo)
- ✅ RoutingProvider (Flutter state management)
- ✅ Atomic channel_count (lock-free FFI query)
- ⚠️ Routing UI Panel (TODO: visual matrix)

### DAW Audio Routing (2026-01-20) ✅

Dve odvojene mixer arhitekture za različite sektore:

| Provider | Sektor | FFI | Namena |
|----------|--------|-----|--------|
| **MixerProvider** | DAW | ✅ | Timeline playback, track routing |
| **MixerDSPProvider** | Middleware/SlotLab | ✅ | Event-based audio, bus mixing |

**MixerProvider** (`mixer_provider.dart`):
- Track volume/pan → `NativeFFI.setTrackVolume/Pan()`
- Bus volume/pan → `engine.setBusVolume/Pan()`
- Mute/Solo → `NativeFFI.setTrackMute/Solo()`, `mixerSetBusMute/Solo()`
- Real-time metering integration

**MixerDSPProvider** (`mixer_dsp_provider.dart`) — UPDATED 2026-01-20:
- Bus volume → `NativeFFI.setBusVolume(engineIdx, volume)`
- Bus pan → `NativeFFI.setBusPan(engineIdx, pan)`
- Mute/Solo → `NativeFFI.setBusMute/Solo(engineIdx, state)`
- `connect()` sinhronizuje sve buseve sa engine-om

**Bus Engine ID Mapping:**
```
sfx=0, music=1, voice=2, ambience=3, aux=4, master=5
```

**Dokumentacija:** `.claude/architecture/DAW_AUDIO_ROUTING.md`

### Unified Playback System (2026-01-21) ✅

Section-based playback isolation — svaka sekcija blokira ostale tokom playback-a.

| Sekcija | Behavior kad krene playback |
|---------|----------------------------|
| **DAW** | SlotLab i Middleware se pauziraju |
| **SlotLab** | DAW i Middleware se pauziraju |
| **Middleware** | DAW i SlotLab se pauziraju |
| **Browser** | Izolovan (PREVIEW_ENGINE) |

**Ključne komponente:**
- `UnifiedPlaybackController` — singleton koji kontroliše `acquireSection` / `releaseSection`
- `TimelinePlaybackProvider` — koristi `acquireSection(PlaybackSection.daw)`
- `SlotLabProvider` — koristi `acquireSection(PlaybackSection.slotLab)`
- `MiddlewareProvider` — koristi `acquireSection(PlaybackSection.middleware)` u `postEvent()`

**Waveform Cache Invalidation:**
- SlotLab koristi dedicirani track ID 99999 za waveform preview (sprečava koliziju sa DAW track-ovima)
- `EditorModeProvider.waveformGeneration` se inkrementira kad se vrati u DAW mode
- `_UltimateClipWaveformState` proverava generation i reload-uje cache ako se promenio

**Dokumentacija:** `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md`

### Advanced Middleware (Wwise/FMOD-style)
- ✅ **Ducking Matrix** — Automatic volume ducking (source→target bus matrix, attack/release/curve)
- ✅ **Blend Containers** — RTPC-based crossfade between sounds (range sliders, curve visualization)
- ✅ **Random Containers** — Weighted random selection (Random/Shuffle/Round Robin modes, pitch/volume variation)
- ✅ **Sequence Containers** — Timed sound sequences (timeline, step editor, loop/hold/ping-pong)
- ✅ **Music System** — Beat/bar synchronized music (tempo, time signature, cue points, stingers)
- ✅ **Attenuation Curves** — Slot-specific curves (Win Amount, Near Win, Combo, Feature Progress)

**Dart Models:** `flutter_ui/lib/models/middleware_models.dart`
**Provider:** `flutter_ui/lib/providers/middleware_provider.dart`
**UI Widgets:** `flutter_ui/lib/widgets/middleware/`
- `advanced_middleware_panel.dart` — Combined tabbed interface
- `ducking_matrix_panel.dart` — Visual matrix editor
- `blend_container_panel.dart` — RTPC crossfade editor
- `random_container_panel.dart` — Weighted random editor
- `sequence_container_panel.dart` — Timeline sequence editor
- `music_system_panel.dart` — Music segments + stingers
- `attenuation_curve_panel.dart` — Curve shape editor

### Advanced Audio Systems (MiddlewareProvider Integration)

Svi advanced sistemi su potpuno integrisani u MiddlewareProvider (linije 3017-3455):

| Sistem | Metode | Opis |
|--------|--------|------|
| **VoicePool** | `requestVoice()`, `releaseVoice()`, `getVoicePoolStats()` | Polyphony management (48 voices, stealing modes) |
| **BusHierarchy** | `getBus()`, `setBusVolume/Mute/Solo()`, `addBusPreInsert()` | Bus routing sa effects |
| **AuxSendManager** | 14 metoda (createAuxSend, setAuxSendLevel, etc.) | Send/Return routing (Reverb A/B, Delay, Slapback) |
| **MemoryManager** | `registerSoundbank()`, `loadSoundbank()`, `getMemoryStats()` | Bank loading, memory budget |
| **ReelSpatial** | `updateReelSpatialConfig()`, `getReelPosition()` | Per-reel stereo positioning |
| **CascadeAudio** | `getCascadeAudioParams()`, `getActiveCascadeLayers()` | Cascade escalation (pitch, reverb, tension) |
| **HdrAudio** | `setHdrProfile()`, `updateHdrConfig()` | Platform-specific audio (Desktop/Mobile/Broadcast) |
| **Streaming** | `updateStreamingConfig()` | Streaming buffer config |
| **EventProfiler** | `recordProfilerEvent()`, `getProfilerStats()` | Latency tracking, voice stats |
| **AutoSpatial** | `registerSpatialAnchor()`, `emitSpatialEvent()` | UI-driven spatial positioning |

**Model fajlovi:**
- `middleware_models.dart` — Core: State, Switch, RTPC, Ducking, Containers
- `advanced_middleware_models.dart` — Advanced: VoicePool, BusHierarchy, AuxSend, Spatial, Memory, HDR

### Slot Lab — Synthetic Slot Engine (IMPLEMENTED)

Fullscreen audio sandbox za slot game audio dizajn.

**Rust Crate:** `crates/rf-slot-lab/`
- `engine.rs` — SyntheticSlotEngine, spin(), forced outcomes
- `symbols.rs` — SymbolSet, ReelStrip, 10 standard symbols
- `paytable.rs` — Paytable, Payline, LineWin evaluation
- `timing.rs` — TimingProfile (normal/turbo/mobile/studio)
- `stages.rs` — StageEvent generation (20+ stage types)
- `config.rs` — GridSpec, VolatilityProfile (low/med/high/studio)

**FFI Bridge:** `crates/rf-bridge/src/slot_lab_ffi.rs`
- `slot_lab_init()` / `slot_lab_shutdown()`
- `slot_lab_spin()` / `slot_lab_spin_forced(outcome: i32)`
- `slot_lab_get_spin_result_json()` / `slot_lab_get_stages_json()`

**Flutter Provider:** `flutter_ui/lib/providers/slot_lab_provider.dart`
- `spin()` / `spinForced(ForcedOutcome)`
- `lastResult` / `lastStages` / `isPlayingStages`
- Auto-triggers MiddlewareProvider events

**UI Widgets:** `flutter_ui/lib/widgets/slot_lab/`
- `stage_trace_widget.dart` — Animated timeline kroz stage evente
- `slot_preview_widget.dart` — Premium slot machine sa animacijama
- `event_log_panel.dart` — Real-time log audio eventa
- `forced_outcome_panel.dart` — Test buttons (keyboard shortcuts 1-0)
- `audio_hover_preview.dart` — Browser sa hover preview

**Forced Outcomes:**
```
1-Lose, 2-SmallWin, 3-BigWin, 4-MegaWin, 5-EpicWin,
6-FreeSpins, 7-JackpotGrand, 8-NearMiss, 9-Cascade, 0-UltraWin
```

**Dokumentacija:** `.claude/architecture/SLOT_LAB_SYSTEM.md`

### Adaptive Layer Engine (ALE) v2.0 — IMPLEMENTED ✅

Data-driven, context-aware, metric-reactive music system za dinamičko audio layering u slot igrama.

**Rust Crate:** `crates/rf-ale/` (~4500 LOC)
- `signals.rs` — Signal system sa normalizacijom (linear/sigmoid/asymptotic)
- `context.rs` — Context definicije, layers, entry/exit policies, narrative arcs
- `rules.rs` — 16 comparison operatora, compound conditions, 6 action tipova
- `stability.rs` — 7 mehanizama stabilnosti (cooldown, hold, hysteresis, decay, prediction)
- `transitions.rs` — 6 sync modova, 10 fade curves, crossfade overlap
- `engine.rs` — Main engine orchestration, lock-free RT communication
- `profile.rs` — JSON profile load/save sa verzionisanjem

**FFI Bridge:** `crates/rf-bridge/src/ale_ffi.rs` (~780 LOC)
- `ale_init()` / `ale_shutdown()` / `ale_tick()`
- `ale_load_profile()` / `ale_export_profile()`
- `ale_enter_context()` / `ale_exit_context()`
- `ale_update_signal()` / `ale_get_signal_normalized()`
- `ale_set_level()` / `ale_step_up()` / `ale_step_down()`
- `ale_get_state()` / `ale_get_layer_volumes()`

**Flutter Provider:** `flutter_ui/lib/providers/ale_provider.dart` (~745 LOC)
- ChangeNotifier state management
- Dart models za signals, contexts, rules, transitions
- Automatic tick loop za engine updates

**Built-in Signals (18+):**
```
winTier, winXbet, consecutiveWins, consecutiveLosses,
winStreakLength, lossStreakLength, balanceTrend, sessionProfit,
featureProgress, multiplier, nearMissIntensity, anticipationLevel,
cascadeDepth, respinsRemaining, spinsInFeature, totalFeatureSpins,
jackpotProximity, turboMode, momentum (derived), velocity (derived)
```

**Stability Mechanisms (7):**
| Mechanism | Opis |
|-----------|------|
| **Global Cooldown** | Minimum time between any level changes |
| **Rule Cooldown** | Per-rule cooldown after firing |
| **Level Hold** | Lock level for duration after change |
| **Hysteresis** | Different thresholds for up vs down |
| **Level Inertia** | Higher levels resist change more |
| **Decay** | Auto-decrease level after inactivity |
| **Prediction** | Anticipate player behavior |

**Dokumentacija:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md`

### Event Registry System (IMPLEMENTED) ✅

Wwise/FMOD-style centralni audio event sistem sa 490+ stage definicija.

**Arhitektura:**
```
STAGE → EventRegistry → AudioEvent → AudioPlayer(s)
          ↓
    Per-layer playback sa delay/offset
```

**Ključne komponente:**

| Komponenta | Opis |
|------------|------|
| `EventRegistry` | Singleton koji mapira stage→event, trigger, stop |
| `AudioEvent` | Event definicija sa `id`, `name`, `stage`, `layers[]`, `duration`, `loop`, `priority` |
| `AudioLayer` | Pojedinačni zvuk sa `audioPath`, `volume`, `pan`, `delay`, `offset`, `busId` |

**Complete Stage System (2026-01-20):**

| Funkcija | Opis | Status |
|----------|------|--------|
| `_pooledEventStages` | Set rapid-fire eventa za voice pooling | ✅ 50+ eventa |
| `_stageToPriority()` | Vraća prioritet 0-100 za stage | ✅ Kompletan |
| `_stageToBus()` | Mapira stage na SpatialBus (reels/sfx/music/vo/ui/ambience) | ✅ Kompletan |
| `_stageToIntent()` | Mapira stage na spatial intent za AutoSpatialEngine | ✅ 300+ mapiranja |

**Priority Levels (0-100):**
```
HIGHEST (80-100): JACKPOT_*, WIN_EPIC/ULTRA, FS_TRIGGER, BONUS_TRIGGER
HIGH (60-79):     SPIN_START, REEL_STOP, WILD_*, SCATTER_*, WIN_BIG
MEDIUM (40-59):   REEL_SPIN, WIN_SMALL, CASCADE_*, FS_SPIN, HOLD_*
LOW (20-39):      UI_*, SYMBOL_LAND, ROLLUP_TICK, WIN_EVAL
LOWEST (0-19):    MUSIC_BASE, AMBIENT_*, ATTRACT_*, IDLE_*
```

**Voice Pooling (rapid-fire events):**
```dart
const _pooledEventStages = {
  'REEL_STOP', 'REEL_STOP_0'..'REEL_STOP_5',
  'CASCADE_STEP', 'CASCADE_SYMBOL_POP',
  'ROLLUP_TICK', 'ROLLUP_TICK_SLOW', 'ROLLUP_TICK_FAST',
  'WIN_LINE_SHOW', 'WIN_SYMBOL_HIGHLIGHT',
  'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER',
  'SYMBOL_LAND', 'WHEEL_TICK', 'TRAIL_MOVE_STEP',
  // ...50+ total
};
```

**Bus Routing:**
| Bus | Stages |
|-----|--------|
| `reels` | REEL_*, SPIN_*, SYMBOL_LAND* |
| `sfx` | WIN_*, JACKPOT_*, CASCADE_*, WILD_*, SCATTER_*, BONUS_*, MULT_* |
| `music` | MUSIC_*, FS_MUSIC*, HOLD_MUSIC*, ATTRACT_* |
| `vo` | *_VOICE, *_VO, ANNOUNCE* |
| `ui` | UI_*, SYSTEM_*, CONNECTION_*, GAME_* |
| `ambience` | AMBIENT_*, IDLE_*, DEMO_* |

**Per-Reel REEL_STOP:**
```
REEL_STOP_0 → Zvuk za prvi reel (pan: -0.8)
REEL_STOP_1 → Zvuk za drugi reel (pan: -0.4)
REEL_STOP_2 → Zvuk za treći reel (pan: 0.0)
REEL_STOP_3 → Zvuk za četvrti reel (pan: +0.4)
REEL_STOP_4 → Zvuk za peti reel (pan: +0.8)
REEL_STOP   → Fallback za sve (ako nema specifičnog)
```

**REEL_SPIN Loop:**
- Trigeruje se automatski na `SPIN_START`
- Zaustavlja se na `REEL_STOP_4` (poslednji reel)
- Koristi `playLoopingToBus()` za seamless loop

**Flow: Stage → Sound:**
```
1. Stage event (npr. REEL_STOP_0) dolazi od SlotLabProvider
2. EventRegistry.triggerStage('REEL_STOP_0')
3. Pronađi AudioEvent koji ima stage='REEL_STOP_0'
4. Za svaki AudioLayer u event.layers:
   - Čekaj layer.delay ms
   - Dobij spatial pan iz _stageToIntent()
   - Dobij bus iz _stageToBus()
   - Pusti audio preko AudioPlaybackService
```

**Fajlovi:**
- `flutter_ui/lib/services/event_registry.dart` — Centralni registry (1350 LOC)
- `flutter_ui/lib/providers/slot_lab_provider.dart` — Stage playback integracija
- `.claude/domains/slot-audio-events-master.md` — Master katalog 490 eventa

**State Persistence:**
- Audio pool, composite events, tracks, event→region mapping
- Čuva se u Provider, preživljava switch između sekcija

### Bidirectional Event Sync (2026-01-21) ✅

Real-time sinhronizacija composite eventa između SlotLab, Middleware i DAW sekcija.

**Single Source of Truth:** `MiddlewareProvider.compositeEvents`

**Sync Flow:**
```
MiddlewareProvider.addLayerToEvent()
    ↓
notifyListeners()
    ↓
┌─────────────────────────────────────┐
│ PARALLEL UPDATES:                   │
│ • SlotLab: _onMiddlewareChanged()   │
│ • Middleware: Consumer rebuilds     │
│ • DAW: context.watch triggers       │
└─────────────────────────────────────┘
```

**Key Fix:** Sync calls moved to `_onMiddlewareChanged` listener (executes AFTER provider updates, not before).

**Dokumentacija:** `.claude/architecture/EVENT_SYNC_SYSTEM.md`

### Engine-Level Source Filtering (2026-01-21) ✅

One-shot voices filtered by active section at Rust engine level.

**PlaybackSource Enum (Rust):**
```rust
pub enum PlaybackSource {
    Daw = 0,       // DAW timeline (uses track mute, not filtered)
    SlotLab = 1,   // Filtered when inactive
    Middleware = 2, // Filtered when inactive
    Browser = 3,   // Always plays (isolated preview)
}
```

**Filtering Logic:**
- DAW voices: Always play (use their own track mute)
- Browser voices: Always play (isolated preview engine)
- SlotLab/Middleware voices: Only play when their section is active

**Key Files:**
- `crates/rf-engine/src/playback.rs` — PlaybackSource enum, filtering in process_one_shot_voices
- `flutter_ui/lib/services/unified_playback_controller.dart` — _setActiveSection()
- `flutter_ui/lib/services/audio_playback_service.dart` — _sourceToEngineId()

**Dokumentacija:** `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md`

### Service Integration (2026-01-20) ✅

Svi middleware servisi su sada pravilno inicijalizovani i međusobno povezani.

**Inicijalizacija u MiddlewareProvider:**
```dart
void _initializeServices() {
  RtpcModulationService.instance.init(this);
  DuckingService.instance.init();
  ContainerService.instance.init(this);
}
```

**EventRegistry._playLayer() integracija:**
```dart
// RTPC volume modulation
if (RtpcModulationService.instance.hasMapping(eventId)) {
  volume = RtpcModulationService.instance.getModulatedVolume(eventId, volume);
}

// Ducking notification
DuckingService.instance.notifyBusActive(layer.busId);
```

**DuckingService sinhronizacija:**
- `addDuckingRule()` → `DuckingService.instance.addRule()`
- `updateDuckingRule()` → `DuckingService.instance.updateRule()`
- `removeDuckingRule()` → `DuckingService.instance.removeRule()`

**Fajlovi:**
- `flutter_ui/lib/providers/middleware_provider.dart` — Service init + ducking sync
- `flutter_ui/lib/services/ducking_service.dart` — `init()` metoda
- `flutter_ui/lib/services/event_registry.dart` — RTPC/Ducking integracija

### Audio Pool System (IMPLEMENTED) ✅

Pre-allocated voice pool za rapid-fire evente (cascade, rollup, reel stops).

**Problem:**
- Kreiranje novih audio player instanci traje 10-50ms
- Za brze evente (CASCADE_STEP svake 300ms) to uzrokuje latenciju

**Rešenje:**
- Pre-alocirani pool voice ID-eva po event tipu
- Pool HIT = instant playback (reuse voice)
- Pool MISS = nova alokacija (sporije)

**Pooled Events:**
```
CASCADE_STEP, ROLLUP_TICK, WIN_LINE_SHOW,
REEL_STOP, REEL_STOP_0..4
```

**Konfiguracija:**
```dart
// Default config
AudioPoolConfig.defaultConfig  // 2-8 voices, 30s idle timeout

// Slot Lab optimized
AudioPoolConfig.slotLabConfig  // 4-12 voices, 60s idle timeout
```

**API:**
```dart
// Acquire voice (plays automatically)
final voiceId = AudioPool.instance.acquire(
  eventKey: 'CASCADE_STEP',
  audioPath: '/path/to/sound.wav',
  busId: 0,  // SFX bus
  volume: 0.8,
);

// Release back to pool
AudioPool.instance.release(voiceId);

// Stats
AudioPool.instance.hitRate      // 0.0 - 1.0
AudioPool.instance.statsString  // Full stats
```

**Fajlovi:**
- `flutter_ui/lib/services/audio_pool.dart` — Pool implementacija
- `flutter_ui/lib/services/event_registry.dart` — Integracija (automatski koristi pool za pooled evente)

### Audio Latency Compensation (IMPLEMENTED) ✅

Fino podešavanje audio-visual sinhronizacije.

**TimingConfig polja:**
```rust
audio_latency_compensation_ms: f64,      // Buffer latency (3-8ms typical)
visual_audio_sync_offset_ms: f64,        // Fine-tune offset
anticipation_audio_pre_trigger_ms: f64,  // Pre-trigger for anticipation
reel_stop_audio_pre_trigger_ms: f64,     // Pre-trigger for reel stops
```

**Profile defaults:**
| Profile | Latency Comp | Reel Pre-trigger | Anticipation Pre-trigger |
|---------|-------------|------------------|-------------------------|
| Normal | 5ms | 20ms | 50ms |
| Turbo | 3ms | 10ms | 30ms |
| Mobile | 8ms | 15ms | 40ms |
| Studio | 3ms | 15ms | 30ms |

**Fajl:** `crates/rf-slot-lab/src/timing.rs`

### Glass Theme Wrappers (IMPLEMENTED) ✅

Premium Glass/Liquid theme za Slot Lab komponente.

**Dostupni wrapperi:**
```dart
GlassSlotLabWrapper        // Base wrapper
GlassSlotPreviewWrapper    // Slot reels (isSpinning, hasWin)
GlassStageTraceWrapper     // Stage timeline (isPlaying)
GlassEventLogWrapper       // Event log panel
GlassForcedOutcomeButtonWrapper  // Test buttons
GlassWinCelebrationWrapper // Win overlay (winTier 1-4)
GlassAudioPoolStats        // Pool performance indicator
```

**Korišćenje:**
```dart
GlassSlotPreviewWrapper(
  isSpinning: _isSpinning,
  hasWin: result?.isWin ?? false,
  child: SlotPreviewWidget(...),
)
```

**Fajl:** `flutter_ui/lib/widgets/glass/glass_slot_lab.dart`

### Slot Lab Audio Improvements (2026-01-20) ✅

Critical (P0) i High-Priority (P1) audio poboljšanja za Slot Lab.

**Sve P0/P1 stavke implementirane:**

| ID | Feature | Status |
|----|---------|--------|
| P0.1 | Audio Latency Compensation | ✅ Done |
| P0.2 | Seamless REEL_SPIN Loop | ✅ Done |
| P0.3 | Per-Voice Pan u FFI | ✅ Done |
| P0.4 | Dynamic Cascade Timing | ✅ Done |
| P0.5 | Dynamic Rollup Speed (RTPC) | ✅ Done |
| P0.6 | Anticipation Pre-Trigger | ✅ Done |
| P0.7 | Big Win Layered Audio | ✅ Done |
| P1.1 | Symbol-Specific Audio | ✅ Done |
| P1.2 | Near Miss Audio Escalation | ✅ Done |
| P1.3 | Win Line Audio Panning | ✅ Done |

**Ključni fajlovi:**
- `crates/rf-engine/src/playback.rs` — Per-voice pan, seamless looping
- `crates/rf-slot-lab/src/timing.rs` — TimingConfig sa latency compensation
- `flutter_ui/lib/services/rtpc_modulation_service.dart` — Rollup/Cascade speed RTPC
- `flutter_ui/lib/services/event_registry.dart` — Big Win templates, context pan/volume
- `flutter_ui/lib/providers/slot_lab_provider.dart` — Pre-trigger, timing config, symbol detection

**Dokumentacija:** `.claude/architecture/SLOT_LAB_AUDIO_FEATURES.md` (kompletni tehnički detalji)

### Adaptive Layer Engine (FULLY IMPLEMENTED) ✅ 2026-01-21

Universal, data-driven layer engine za dinamičnu game muziku — **KOMPLETNO IMPLEMENTIRANO**.

**Filozofija:** Od "pusti zvuk X" do "igra je u emotivnom stanju Y".

**Implementacija:**

| Komponenta | Lokacija | LOC | Status |
|------------|----------|-----|--------|
| **rf-ale crate** | `crates/rf-ale/` | ~4500 | ✅ Done |
| **FFI Bridge** | `crates/rf-bridge/src/ale_ffi.rs` | ~780 | ✅ Done |
| **Dart Provider** | `flutter_ui/lib/providers/ale_provider.dart` | ~745 | ✅ Done |
| **UI Widgets** | `flutter_ui/lib/widgets/ale/` | ~3000 | ✅ Done |

**Core Concepts:**

| Koncept | Opis |
|---------|------|
| **Context** | Game chapter (BASE, FREESPINS, HOLDWIN, etc.) — definiše dostupne layere |
| **Layer** | Intensity level L1-L5 — energetski stepen, ne konkretni audio fajl |
| **Signals** | Runtime metrike (winTier, winXbet, momentum, etc.) koje pokreću tranzicije |
| **Rules** | Uslovi za promenu levela (npr. "if winXbet > 10 → step_up") |
| **Stability** | 7 mehanizama za stabilne, predvidljive tranzicije |
| **Transitions** | Beat/bar/phrase sync, 10 fade curves, crossfade overlap |

**Built-in Signals (18+):**
```
winTier, winXbet, consecutiveWins, consecutiveLosses,
winStreakLength, lossStreakLength, balanceTrend, sessionProfit,
featureProgress, multiplier, nearMissIntensity, anticipationLevel,
cascadeDepth, respinsRemaining, spinsInFeature, totalFeatureSpins,
jackpotProximity, turboMode, momentum (derived), velocity (derived)
```

**Stability Mechanisms (7):**
| Mechanism | Opis |
|-----------|------|
| **Global Cooldown** | Minimum vreme između bilo kojih promena levela |
| **Rule Cooldown** | Per-rule cooldown posle aktivacije |
| **Level Hold** | Zaključaj level na određeno vreme posle promene |
| **Hysteresis** | Različiti pragovi za gore vs dole |
| **Level Inertia** | Viši nivoi su "lepljiviji" (teže padaju) |
| **Decay** | Auto-smanjenje levela posle neaktivnosti |
| **Prediction** | Anticipacija ponašanja igrača |

**Transition Profiles:**
- `immediate` — Instant switch (za urgentne evente)
- `beat` — Na sledećem beat-u
- `bar` — Na sledećem taktu
- `phrase` — Na sledećoj muzičkoj frazi (4 takta)
- `next_downbeat` — Na sledećem downbeat-u
- `custom` — Custom grid pozicija

**Fade Curves (10):**
`linear`, `ease_in_quad`, `ease_out_quad`, `ease_in_out_quad`,
`ease_in_cubic`, `ease_out_cubic`, `ease_in_out_cubic`,
`ease_in_expo`, `ease_out_expo`, `s_curve`

**FFI API:**
```rust
ale_init() / ale_shutdown() / ale_tick()
ale_load_profile() / ale_export_profile()
ale_enter_context() / ale_exit_context()
ale_update_signal() / ale_get_signal_normalized()
ale_set_level() / ale_step_up() / ale_step_down()
ale_get_state() / ale_get_layer_volumes()
ale_set_tempo() / ale_set_time_signature()
```

**UI Widgets:** `flutter_ui/lib/widgets/ale/`

| Widget | Fajl | LOC | Opis |
|--------|------|-----|------|
| **AlePanel** | `ale_panel.dart` | ~600 | Glavni panel sa 4 taba (Contexts, Rules, Transitions, Stability) |
| **SignalMonitor** | `signal_monitor.dart` | ~350 | Real-time signal vizualizacija sa sparkline graficima |
| **LayerVisualizer** | `layer_visualizer.dart` | ~400 | Audio layer bars sa volume kontrolama |
| **ContextEditor** | `context_editor.dart` | ~350 | Context lista sa enter/exit akcijama |
| **RuleEditor** | `rule_editor.dart` | ~630 | Rule lista sa filterima, uslovima i akcijama |
| **TransitionEditor** | `transition_editor.dart` | ~450 | Transition profili sa sync mode i fade curve preview |
| **StabilityConfigPanel** | `stability_config_panel.dart` | ~300 | Stability konfiguracija (timing, hysteresis, inertia, decay) |

**Slot Lab Integration:**
- `SlotLabProvider.connectAle()` — Povezuje ALE provider
- `_syncAleSignals()` — Automatski sync spin rezultata na ALE signale
- `_syncAleContext()` — Automatsko prebacivanje konteksta (BASE/FREESPINS/BIGWIN)
- ALE tab u middleware lower zone (uz Events Folder i Event Editor)

**Dokumentacija:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md` (~2350 LOC)

---

### Universal Stage Ingest System (PLANNED)

Slot-agnostički sistem za integraciju sa bilo kojim game engine-om.

**Filozofija:** FluxForge ne razume tuđe evente — razume samo **STAGES** (semantičke faze toka igre).

```
Engine JSON/Events → Adapter → STAGES → FluxForge Audio
```

**Kanonske STAGES:**
- `SPIN_START`, `REEL_SPIN`, `REEL_STOP`, `REEL_STOP_0..4`
- `ANTICIPATION_ON/OFF`, `WIN_PRESENT`, `ROLLUP_START/END`
- `BIGWIN_TIER`, `FEATURE_ENTER/STEP/EXIT`, `CASCADE_STEP`
- `JACKPOT_TRIGGER`, `BONUS_ENTER/EXIT`

**Tri sloja ingesta:**
1. **Direct Event** — Engine ima event log → mapiranje imena
2. **Snapshot Diff** — Engine ima samo pre/posle stanje → diff derivation
3. **Rule-Based** — Generički eventi → heuristička rekonstrukcija

**Dva režima rada:**
| Mode | Opis |
|------|------|
| **OFFLINE** | JSON import → Adapter Wizard → StageTrace → Audio dizajn |
| **LIVE** | WebSocket/TCP → Real-time STAGES → Live audio preview |

**Crates (planned):**
- `rf-stage` — Stage enum, StageEvent, StageTrace, TimingResolver
- `rf-ingest` — Adapter trait, registry, 3 ingest layers, Wizard
- `rf-connector` — WebSocket/TCP connection, live event streaming
- `adapters/rf-adapter-*` — Per-company adapters (IGT, Aristocrat, etc.)

**Dokumentacija:**
- `.claude/architecture/STAGE_INGEST_SYSTEM.md`
- `.claude/architecture/ENGINE_INTEGRATION_SYSTEM.md`
- `.claude/architecture/SLOT_LAB_SYSTEM.md`
- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — **KRITIČNO: Unified playback across DAW/Middleware/SlotLab**
- `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md` — **Universal Layer Engine: context-aware, metric-reactive music system**

---

Za detalje: `.claude/project/fluxforge-studio.md`
