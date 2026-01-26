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

**UVEK FULL BUILD SA RUST-OM** — bez izuzetaka:

```bash
# KILL existing
pkill -f "FluxForge" 2>/dev/null || true

# 1. BUILD RUST
cd "/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio" && \
cargo build --release && \

# 2. COPY DYLIBS TO FRAMEWORKS
cp target/release/librf_bridge.dylib flutter_ui/macos/Frameworks/ && \
cp target/release/librf_engine.dylib flutter_ui/macos/Frameworks/ && \

# 3. BUILD + RUN FLUTTER
cd flutter_ui/macos && \
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
- UVEK kopirati dylib-ove i u APP BUNDLE (xcodebuild NE kopira!)

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
- **NIKADA jednostavno rešenje — UVEK ultimativno** → ako postoji name collision, preimenuj klasu; ako treba refactor, uradi ga kompletno
- **AUTOMATSKI ČITAJ pre promene** → pre bilo kakve izmene UVEK pročitaj sve relevantne fajlove, pronađi SVE instance, razumi kontekst

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
| **decoder.rs** | Universal audio decoder (WAV, FLAC, MP3, OGG, AAC, AIFF via symphonia) |
| **encoder.rs** | Multi-format encoder (WAV 16/24/32f, FLAC, MP3) |
| **normalize.rs** | EBU R128 LUFS metering with K-weighting, True Peak detection (4x oversampling) |
| **pipeline.rs** | Job-based processing pipeline with progress callbacks |
| **time_stretch.rs** | Phase vocoder time stretching |

**Key Features:**
| Feature | Description |
|---------|-------------|
| **EBU R128 LUFS** | Integrated, short-term, momentary loudness with K-weighting filters |
| **True Peak** | 4x oversampled ISP detection for streaming compliance |
| **Format Conversion** | Decode any → process → encode to target format |
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

## 🏗️ DEPENDENCY INJECTION — GetIt Service Locator

**Status:** ✅ IMPLEMENTED (2026-01-21)

### Service Locator Pattern

```dart
// Global instance
final GetIt sl = GetIt.instance;

// Access services anywhere
final ffi = sl<NativeFFI>();
final pool = sl<AudioPool>();
final stateGroups = sl<StateGroupsProvider>();
```

### Registered Services (by layer)

| Layer | Service | Type |
|-------|---------|------|
| 1 | `NativeFFI` | Core FFI |
| 2 | `SharedMeterReader`, `WaveformCacheService`, `AudioAssetManager`, `LiveEngineService` | Low-level |
| 3 | `UnifiedPlaybackController`, `AudioPlaybackService`, `AudioPool`, `SlotLabTrackBridge`, `SessionPersistenceService` | Playback |
| 4 | `DuckingService`, `RtpcModulationService`, `ContainerService`, `DuckingPreviewService` | Audio processing |
| 5 | `StateGroupsProvider`, `SwitchGroupsProvider`, `RtpcSystemProvider`, `DuckingSystemProvider`, `EventSystemProvider`, `CompositeEventSystemProvider` | Middleware subsystems |
| 5.5 | `SlotLabProjectProvider` | SlotLab V6 project state (symbols, contexts, layers) |
| 6 | `BusHierarchyProvider`, `AuxSendProvider` | Bus routing subsystems |
| 7 | `StageIngestProvider` | Stage Ingest (engine integration) |
| 8 | `WorkspacePresetService` | Layout presets (M3.2) |
| 9 | `MathModelConnector` | Win tier → RTPC bridge (M4) |

### Subsystem Providers (extracted from MiddlewareProvider)

| Provider | File | LOC | Manages |
|----------|------|-----|---------|
| `StateGroupsProvider` | `providers/subsystems/state_groups_provider.dart` | ~185 | Global state groups (Wwise-style) |
| `SwitchGroupsProvider` | `providers/subsystems/switch_groups_provider.dart` | ~210 | Per-object switches |
| `RtpcSystemProvider` | `providers/subsystems/rtpc_system_provider.dart` | ~350 | RTPC definitions, bindings, curves |
| `DuckingSystemProvider` | `providers/subsystems/ducking_system_provider.dart` | ~190 | Ducking rules (sidechain matrix) |
| `EventSystemProvider` | `providers/subsystems/event_system_provider.dart` | ~330 | MiddlewareEvent CRUD, FFI sync |
| `CompositeEventSystemProvider` | `providers/subsystems/composite_event_system_provider.dart` | ~1280 | SlotCompositeEvent CRUD, undo/redo, layer ops, stage triggers |
| `BusHierarchyProvider` | `providers/subsystems/bus_hierarchy_provider.dart` | ~360 | Audio bus hierarchy (Wwise-style routing) |
| `AuxSendProvider` | `providers/subsystems/aux_send_provider.dart` | ~390 | Aux send/return routing (Reverb, Delay, Slapback) |
| `VoicePoolProvider` | `providers/subsystems/voice_pool_provider.dart` | ~340 | Voice polyphony, stealing, virtual voices + FFI engine stats |
| `AttenuationCurveProvider` | `providers/subsystems/attenuation_curve_provider.dart` | ~300 | Slot-specific attenuation curves |
| `MemoryManagerProvider` | `providers/subsystems/memory_manager_provider.dart` | ~350 | Soundbank memory management, LRU unloading + FFI backend |
| `EventProfilerProvider` | `providers/subsystems/event_profiler_provider.dart` | ~540 | Audio event profiling, latency tracking + DSP profiler FFI |

**Decomposition Progress:**
- Phase 1 ✅: StateGroups + SwitchGroups
- Phase 2 ✅: RTPC + Ducking
- Phase 3 ✅: Containers (Blend/Random/Sequence providers)
- Phase 4 ✅: Music + Events (MusicSystemProvider, EventSystemProvider, CompositeEventSystemProvider)
- Phase 5 ✅: Bus Routing (BusHierarchyProvider, AuxSendProvider)
- Phase 6 ✅: VoicePool + AttenuationCurves
- Phase 7 ✅: MemoryManager + EventProfiler

**Usage in MiddlewareProvider:**
```dart
MiddlewareProvider(this._ffi) {
  _stateGroupsProvider = sl<StateGroupsProvider>();
  _switchGroupsProvider = sl<SwitchGroupsProvider>();
  _rtpcSystemProvider = sl<RtpcSystemProvider>();
  _duckingSystemProvider = sl<DuckingSystemProvider>();
  _busHierarchyProvider = sl<BusHierarchyProvider>();
  _auxSendProvider = sl<AuxSendProvider>();
  _voicePoolProvider = sl<VoicePoolProvider>();
  _attenuationCurveProvider = sl<AttenuationCurveProvider>();
  _memoryManagerProvider = sl<MemoryManagerProvider>();
  _eventProfilerProvider = sl<EventProfilerProvider>();

  // Forward notifications from subsystems
  _stateGroupsProvider.addListener(notifyListeners);
  _switchGroupsProvider.addListener(notifyListeners);
  _rtpcSystemProvider.addListener(notifyListeners);
  _duckingSystemProvider.addListener(notifyListeners);
  _busHierarchyProvider.addListener(notifyListeners);
  _auxSendProvider.addListener(notifyListeners);
  _voicePoolProvider.addListener(notifyListeners);
  _attenuationCurveProvider.addListener(notifyListeners);
  _memoryManagerProvider.addListener(notifyListeners);
  _eventProfilerProvider.addListener(notifyListeners);
}
```

**FFI Integration Summary (2026-01-24):**

All 16 subsystem providers are connected to Rust FFI:

| Provider | FFI Backend | Status |
|----------|-------------|--------|
| StateGroupsProvider | `middleware_*` | ✅ State group registration |
| SwitchGroupsProvider | `middleware_*` | ✅ Per-object switches |
| RtpcSystemProvider | `middleware_*` | ✅ RTPC bindings |
| DuckingSystemProvider | `middleware_*` | ✅ Ducking rules |
| BlendContainersProvider | `container_*` | ✅ RTPC crossfade |
| RandomContainersProvider | `container_*` | ✅ Weighted random |
| SequenceContainersProvider | `container_*` | ✅ Timed sequences |
| MusicSystemProvider | `middleware_*` | ✅ Music segments |
| EventSystemProvider | `middleware_*` | ✅ Event CRUD |
| CompositeEventSystemProvider | — | Dart-only (EventRegistry) |
| BusHierarchyProvider | `mixer_*` | ✅ Bus routing |
| AuxSendProvider | — | Dart-only aux routing |
| **VoicePoolProvider** | `getVoicePoolStats` | ✅ Engine voice stats |
| AttenuationCurveProvider | — | Dart curve evaluation |
| **MemoryManagerProvider** | `memory_manager_*` | ✅ Full memory manager |
| **EventProfilerProvider** | `profiler_*` | ✅ DSP profiler |

**Dokumentacija:**
- `.claude/SYSTEM_AUDIT_2026_01_21.md` — P0.2 progress
- `.claude/architecture/MIDDLEWARE_DECOMPOSITION.md` — Full decomposition plan (Phase 1-7 complete)

### Middleware Deep Analysis (2026-01-24) ✅ COMPLETE

Kompletna analiza 6 ključnih middleware komponenti iz svih 7 CLAUDE.md uloga.

**Summary:**

| # | Komponenta | LOC | P1 Fixed | Status |
|---|------------|-----|----------|--------|
| 1 | EventRegistry | ~1645 | 4 | ✅ DONE |
| 2 | CompositeEventSystemProvider | ~1448 | 3 | ✅ DONE |
| 3 | Container Panels (Blend/Random/Sequence) | ~3653 | 1 | ✅ DONE |
| 4 | ALE Provider | ~837 | 2 | ✅ DONE |
| 5 | Lower Zone Controller | ~498 | 0 | ✅ CLEAN |
| 6 | Stage Ingest Provider | ~1270 | 0 | ✅ CLEAN |
| **TOTAL** | **~9351 LOC** | **10** | **~335 LOC fixes** |

**P1 Fixes Implemented:**

| Fix | File | LOC |
|-----|------|-----|
| AudioContext resume na first play | `event_registry.dart` | ~35 |
| triggerStage null event handling | `event_registry.dart` | ~28 |
| Voice limit check pre playback | `event_registry.dart` | ~42 |
| Loop cleanup on stopEvent | `event_registry.dart` | ~45 |
| Dispose cleanup (listeners, timers) | `composite_event_system_provider.dart` | ~55 |
| Undo stack bounds check | `composite_event_system_provider.dart` | ~32 |
| Layer ID uniqueness validation | `composite_event_system_provider.dart` | ~40 |
| Disposed state check in async ops | `blend_container_panel.dart` | ~8 |
| Context mounted check in tick | `ale_provider.dart` | ~25 |
| Parameter clamping in setLevel | `ale_provider.dart` | ~25 |

**P2 Fixes Implemented:**

| Fix | File | LOC | Note |
|-----|------|-----|------|
| Crossfade for loop stop | — | 0 | Already in Rust (`start_fade_out(240)`) |
| Pan smoothing | — | 0 | N/A (pan fixed at voice creation) |
| Level clamping | `ale_provider.dart` | +10 | Clamps 0-4 |
| Poll loop bounded | `stage_ingest_provider.dart` | +12 | Max 100 events/tick |
| Child count limit (32 max) | `middleware_provider.dart` | +18 | Prevents memory exhaustion |
| Name/category XSS sanitization | `composite_event_system_provider.dart` | +45 | Blocks HTML tags and entities |
| WebSocket URL validation | `stage_ingest_provider.dart` | +45 | Validates scheme, host, port |

**Total P2:** +130 LOC

**Analysis Documents:**
- `.claude/analysis/EVENT_REGISTRY_ANALYSIS_2026_01_24.md`
- `.claude/analysis/COMPOSITE_EVENT_PROVIDER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/CONTAINER_PANELS_ANALYSIS_2026_01_24.md`
- `.claude/analysis/ALE_PROVIDER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/LOWER_ZONE_CONTROLLER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/STAGE_INGEST_PROVIDER_ANALYSIS_2026_01_24.md`
- `.claude/analysis/MIDDLEWARE_DEEP_ANALYSIS_PLAN.md` — Master tracking doc

### Lower Zone Services & Providers (2026-01-22)

| Service/Provider | File | LOC | Purpose |
|------------------|------|-----|---------|
| `TrackPresetService` | `services/track_preset_service.dart` | ~450 | Track preset CRUD, factory presets |
| `DspChainProvider` | `providers/dsp_chain_provider.dart` | ~400 | Per-track DSP chain, drag-drop reorder |

**TrackPresetService** (Singleton):
```dart
TrackPresetService.instance.loadPresets();
TrackPresetService.instance.savePreset(preset);
TrackPresetService.instance.deletePreset(name);
```

**DspChainProvider** (ChangeNotifier):
```dart
final chain = provider.getChain(trackId);
provider.addNode(trackId, DspNodeType.compressor);
provider.swapNodes(trackId, nodeIdA, nodeIdB);
provider.toggleNodeBypass(trackId, nodeId);
```

**DspNodeType Enum:** `eq`, `compressor`, `limiter`, `gate`, `reverb`, `delay`, `saturation`, `deEsser`

**LowerZonePersistenceService** (Singleton):
```dart
// Initialize once at startup (main.dart)
await LowerZonePersistenceService.instance.init();

// Save/Load per section
await LowerZonePersistenceService.instance.saveDawState(state);
final dawState = await LowerZonePersistenceService.instance.loadDawState();

await LowerZonePersistenceService.instance.saveMiddlewareState(state);
await LowerZonePersistenceService.instance.saveSlotLabState(state);
```

**Persisted State Types:**
| Type | Fields |
|------|--------|
| `DawLowerZoneState` | activeTab, isExpanded, height |
| `MiddlewareLowerZoneState` | activeTab, isExpanded, height |
| `SlotLabLowerZoneState` | activeTab, isExpanded, height |

**Storage:** SharedPreferences (JSON serialization)

**Dokumentacija:** `.claude/architecture/LOWER_ZONE_ENGINE_ANALYSIS.md`

### Lower Zone Layout Architecture (2026-01-23) ✅

Unified height calculation and overflow-safe layout system for all Lower Zone widgets.

**Height Constants** (`lower_zone_types.dart`):
| Constant | Value | Description |
|----------|-------|-------------|
| `kLowerZoneMinHeight` | 150.0 | Minimum content height |
| `kLowerZoneMaxHeight` | 600.0 | Maximum content height |
| `kLowerZoneDefaultHeight` | 500.0 | Default content height |
| `kContextBarHeight` | 60.0 | Super-tabs + sub-tabs (expanded) |
| `kContextBarCollapsedHeight` | 32.0 | Super-tabs only (collapsed) |
| `kActionStripHeight` | 36.0 | Bottom action buttons |
| `kResizeHandleHeight` | 4.0 | Drag resize handle |
| `kSpinControlBarHeight` | 32.0 | SlotLab spin controls |

**Total Height Calculation** (`slotlab_lower_zone_controller.dart`):
```dart
double get totalHeight => isExpanded
    ? height + kContextBarHeight + kActionStripHeight + kResizeHandleHeight + kSpinControlBarHeight
    : kResizeHandleHeight + kContextBarCollapsedHeight;  // 32px when collapsed
```

**Layout Structure** (overflow-safe):
```
AnimatedContainer (totalHeight, clipBehavior: Clip.hardEdge)
└── Column (NO mainAxisSize.min — fills container)
    ├── ResizeHandle (4px fixed)
    ├── ContextBar (32px collapsed / 60px expanded)
    └── Expanded (only when expanded)
        └── Column (NO mainAxisSize.min — fills Expanded)
            ├── SpinControlBar (32px fixed, SlotLab only)
            ├── Expanded → ClipRect → ContentPanel (flexible)
            └── ActionStrip (36px fixed)
```

**Critical Layout Rules:**
- **NEVER** use `mainAxisSize: MainAxisSize.min` on Column inside Expanded
- Column inside AnimatedContainer with fixed height should fill the container
- ContextBar height is dynamic: 32px collapsed, 60px expanded

**Compact Panel Pattern**:
```dart
Widget _buildCompactPanel() {
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header (fixed)
        _buildPanelHeader('TITLE', Icons.icon),
        const SizedBox(height: 8),
        // Content (flexible, bounded)
        Flexible(
          fit: FlexFit.loose,
          child: Container(
            clipBehavior: Clip.hardEdge,
            child: ListView.builder(shrinkWrap: true, ...),
          ),
        ),
      ],
    ),
  );
}
```

**Key Rules**:
- Always use `clipBehavior: Clip.hardEdge` on scroll containers
- Use `Flexible(fit: FlexFit.loose)` instead of `Expanded` for content
- Use `shrinkWrap: true` on ListView/GridView inside flexible containers
- Use `LayoutBuilder` to pass available height to child panels
- Never hardcode panel heights — use constraints from LayoutBuilder

**Overflow Fixes (2026-01-23):**

| Issue | Root Cause | Fix |
|-------|------------|-----|
| Empty space below tabs when collapsed | ContextBar had fixed 60px but showed only 32px | Dynamic height: `isExpanded ? 60 : 32` |
| Layout conflict in nested Columns | `mainAxisSize: MainAxisSize.min` inside Expanded | Removed — Column fills Expanded |
| Wrong totalHeight when collapsed | Used `kContextBarHeight` (60) | Use `kContextBarCollapsedHeight` (32) |

**Files Changed:**
- `lower_zone_types.dart` — Added `kContextBarCollapsedHeight = 32.0`
- `lower_zone_context_bar.dart` — Dynamic height based on `isExpanded`
- `slotlab_lower_zone_controller.dart` — Fixed collapsed totalHeight calculation
- `slotlab_lower_zone_widget.dart` — Removed `mainAxisSize.min` from both Columns

**SlotLab Connected Panels** (`slotlab_lower_zone_widget.dart`):

| Panel | Provider | Data Source | Status |
|-------|----------|-------------|--------|
| Stage Trace | SlotLabProvider | `lastStages` | ✅ Connected |
| Event Timeline | SlotLabProvider | `lastStages` | ✅ Connected |
| Symbols Panel | MiddlewareProvider | `compositeEvents` (SYMBOL_LAND_*) | ✅ Connected |
| Event Folder | MiddlewareProvider | `compositeEvents`, categories | ✅ Connected |
| Composite Editor | MiddlewareProvider | `compositeEvents`, layers | ✅ Connected |
| Event Log | SlotLab + Middleware | Both providers | ✅ Connected |
| Voice Pool | MiddlewareProvider | `getVoicePoolStats()` | ✅ Connected |
| Bus Hierarchy | (Standalone) | BusHierarchyPanel | ✅ Connected |
| Aux Sends | (Standalone) | AuxSendsPanel | ✅ Connected |
| Profiler | (Standalone) | ProfilerPanel | ✅ Connected |
| Bus Meters | NativeFFI | Real-time metering | ✅ Connected |
| Batch Export | MiddlewareProvider | Events export | ✅ Connected |
| Stems Panel | Engine buses | Bus configuration | ✅ Connected |
| Variations | MiddlewareProvider | `randomContainers` | ✅ Connected |
| Package Panel | MiddlewareProvider | `compositeEvents.length` | ✅ Connected |
| FabFilter DSP | FabFilter widgets | EQ, Compressor, Reverb | ✅ Connected |

**No More Placeholders** — All panels connected to real data sources.

### Interactive Layer Parameter Editing (2026-01-24) ✅

Composite Editor now has interactive slider controls for layer parameters.

**Implementation:** `_buildInteractiveLayerItem()` in `slotlab_lower_zone_widget.dart`

| Parameter | UI Control | Range | Provider Method |
|-----------|------------|-------|-----------------|
| Volume | Slider | 0-100% | `updateEventLayer(eventId, layer.copyWith(volume: v))` |
| Pan | Slider | L100-C-R100 | `updateEventLayer(eventId, layer.copyWith(pan: v))` |
| Delay | Slider | 0-2000ms | `updateEventLayer(eventId, layer.copyWith(offsetMs: v))` |
| Mute | Toggle | On/Off | `updateEventLayer(eventId, layer.copyWith(volume: 0))` |
| Preview | Button | - | `AudioPlaybackService.previewFile()` |
| Delete | Button | - | `removeLayerFromEvent(eventId, layerId)` |

**Helper:**
```dart
Widget _buildParameterSlider({
  required String label,
  required double value,
  required ValueChanged<double> onChanged,
});
```

**Features:**
- Real-time parameter updates via MiddlewareProvider
- Compact slider UI optimized for Lower Zone height
- Audio preview button for quick auditioning
- All changes persist to SSoT (MiddlewareProvider.compositeEvents)

### Lower Zone Action Strip Integration (2026-01-23) ✅

All three Lower Zone widgets now have fully connected action buttons in their Action Strips.

**Architecture:**
```
LowerZoneActionStrip
├── actions: List<LowerZoneAction>
│   ├── label: String
│   ├── icon: IconData
│   ├── onTap: VoidCallback?  ← MUST BE CONNECTED!
│   ├── isPrimary: bool
│   └── isDestructive: bool
├── accentColor: Color
└── statusText: String?
```

**SlotLab Action Strip** (`slotlab_lower_zone_widget.dart`) — ✅ FULLY CONNECTED (2026-01-24):

| Super Tab | Actions | Connected To |
|-----------|---------|--------------|
| **Stages** | Record, Stop, Clear, Export | `SlotLabProvider.startStageRecording()`, `stopStageRecording()`, `clearStages()` |
| **Events** | Add Layer, Remove, Duplicate, Preview | `AudioWaveformPickerDialog`, `MiddlewareProvider.removeLayerFromEvent()`, `duplicateCompositeEvent()`, `previewCompositeEvent()` |
| **Mix** | Mute, Solo, Reset, Meters | `MixerDSPProvider.toggleMute/Solo()`, `reset()` ✅ |
| **DSP** | Insert, Remove, Reorder, Copy Chain | `DspChainProvider.addNode()` with popup menu, `removeNode()`, `swapNodes()` ✅ |
| **Bake** | Validate, Bake All, Package | Validation logic + `_buildPackageExport()` FilePicker flow ✅ |

**Middleware Action Strip** (`middleware_lower_zone_widget.dart`) — ✅ CONNECTED (2026-01-24):

| Super Tab | Actions | Connected To |
|-----------|---------|--------------|
| **Events** | New Event, Delete, Duplicate, Test | ✅ `MiddlewareProvider.createCompositeEvent()`, `deleteCompositeEvent()`, `duplicateCompositeEvent()`, `previewCompositeEvent()` |
| **Containers** | Add Sound, Balance, Shuffle, Test | ⚠️ debugPrint (provider methods not implemented) |
| **Routing** | Add Rule, Remove, Copy, Test | ✅ `MiddlewareProvider.addDuckingRule()`, ducking matrix actions |
| **RTPC** | Add Point, Remove, Reset, Preview | ⚠️ debugPrint (provider methods not implemented) |
| **Deliver** | Validate, Bake, Package | ⚠️ debugPrint (export service TODO) |

**Note:** Containers, RTPC, and Deliver actions use debugPrint workarounds because the underlying provider methods don't exist yet. Events and Routing are fully functional.

**Middleware Layer Parameter Strip** (2026-01-24) ✅

When Events tab is active and an event is selected, a comprehensive parameter strip appears above the action buttons:

| Parameter | Widget | Range | Provider Method |
|-----------|--------|-------|-----------------|
| **Volume** | Slider + dB | 0.0–2.0 (−∞ to +6dB) | `updateEventLayer(layer.copyWith(volume))` |
| **Pan** | Slider | −1.0 to +1.0 (L/R) | `updateEventLayer(layer.copyWith(pan))` |
| **Bus** | Dropdown | SFX/Music/Voice/Ambience/Aux/Master | `updateEventLayer(layer.copyWith(busId))` |
| **Offset** | Slider + ms | 0–2000ms | `updateEventLayer(layer.copyWith(offsetMs))` |
| **Mute** | Toggle | On/Off | `updateEventLayer(layer.copyWith(muted))` |
| **Solo** | Toggle | On/Off | `updateEventLayer(layer.copyWith(solo))` |
| **Loop** | Toggle | On/Off | `updateCompositeEvent(event.copyWith(looping))` |
| **ActionType** | Dropdown | Play/Stop/Pause/SetVolume | `updateEventLayer(layer.copyWith(actionType))` |

**Helper Methods (~170 LOC):**
- `_buildLayerParameterStrip()` — Main strip builder
- `_buildCompactVolumeControl()` — Volume slider with dB conversion
- `_buildCompactBusSelector()` — Bus dropdown with color coding
- `_buildCompactOffsetControl()` — Delay slider with ms display
- `_buildMuteSoloToggles()` — Mute/Solo toggle buttons
- `_buildLoopToggle()` — Loop toggle (event-level)
- `_buildActionTypeSelector()` — ActionType dropdown

**FFI Flow:** Parameters → `EventRegistry._playLayer()` → `AudioPlaybackService.playFileToBus(path, volume, pan, busId, source)` or `playLoopingToBus()` if loop=true

**DAW Action Strip** (`daw_lower_zone_widget.dart`) — ✅ FULLY CONNECTED (2026-01-24):

| Super Tab | Actions | Connected To |
|-----------|---------|--------------|
| **Browse** | Import, Delete, Preview, Add | ✅ FilePicker, AudioAssetManager, AudioPlaybackService |
| **Edit** | Add Track, Split, Duplicate, Delete | ✅ MixerProvider.addChannel(), DspChainProvider |
| **Mix** | Add Bus, Mute All, Solo, Reset | ✅ MixerProvider.addBus/muteAll/clearAllSolo/resetAll |
| **Process** | Add EQ, Remove, Copy, Bypass | ✅ DspChainProvider.addNode/removeNode/setBypass |
| **Deliver** | Quick Export, Browse, Export | ✅ FilePicker, Process.run (folder open) |

**Pan Law Integration (2026-01-24):**
- `_stringToPanLaw()` — Converts '0dB', '-3dB', '-4.5dB', '-6dB' to PanLaw enum
- `_applyPanLaw()` — Calls `stereoImagerSetPanLaw()` FFI for all tracks

**New Provider Methods (2026-01-23):**

**SlotLabProvider:**
```dart
bool _isRecordingStages = false;
bool get isRecordingStages => _isRecordingStages;

void startStageRecording();   // Start recording stage events
void stopStageRecording();    // Stop recording
void clearStages();           // Clear all captured stages
```

**MiddlewareProvider:**
```dart
void duplicateCompositeEvent(String eventId);  // Copy event with all layers/stages
void previewCompositeEvent(String eventId);    // Play event audio
```

**Key Files:**
- `lower_zone_action_strip.dart` — Action definitions (`DawActions`, `MiddlewareActions`, `SlotLabActions`)
- `slotlab_lower_zone_widget.dart:2199` — SlotLab action strip builder
- `middleware_lower_zone_widget.dart:1492` — Middleware action strip builder
- `daw_lower_zone_widget.dart:4088` — DAW action strip builder

### Lower Zone Placeholder Cleanup (2026-01-23) ✅

**Status:** All placeholder code removed — no "Coming soon..." panels.

Uklonjene `_buildPlaceholderPanel` metode iz sva tri Lower Zone widgeta:

| Widget | Lines Removed |
|--------|---------------|
| `slotlab_lower_zone_widget.dart` | ~26 LOC |
| `middleware_lower_zone_widget.dart` | ~26 LOC + outdated comment |
| `daw_lower_zone_widget.dart` | ~26 LOC |

**Svi paneli su sada connected na real data sources** — nema više placeholder-a.

### DAW Lower Zone Feature Improvements (2026-01-23) ✅

Complete 18-task improvement plan for DAW section.

#### P0: Critical Fixes (Completed)
| Task | Description | File |
|------|-------------|------|
| P0.1 | DspChainProvider FFI sync | `dsp_chain_provider.dart` |
| P0.2 | RoutingProvider FFI verification | `routing_provider.dart` |
| P0.3 | MIDI piano roll in EDIT tab | `piano_roll_widget.dart` |
| P0.4 | History panel with undo list | `daw_lower_zone_widget.dart` |
| P0.5 | FX Chain editor in PROCESS tab | `daw_lower_zone_widget.dart` |

#### P1: High Priority Features (Completed)
| Task | Description | File |
|------|-------------|------|
| P1.1 | DspChainProvider ↔ MixerProvider sync | `dsp_chain_provider.dart` |
| P1.2 | FabFilter panels use central DSP state | `fabfilter_panel_base.dart` |
| P1.3 | Send Matrix in MIX > Sends | `routing_matrix_panel.dart` |
| P1.4 | Timeline Settings (tempo, time sig) | `daw_lower_zone_widget.dart` |
| P1.5 | Plugin search in BROWSE > Plugins | `plugin_provider.dart` |
| P1.6 | Rubber band multi-clip selection | `timeline.dart` |

#### P2: Medium Priority Features (Completed)
| Task | Description | File |
|------|-------------|------|
| P2.1 | AudioAssetManager in Files browser | `daw_files_browser.dart` |
| P2.2 | Favorites/bookmarks in Files browser | `daw_files_browser.dart` |
| P2.3 | Interactive Automation Editor | `daw_lower_zone_widget.dart` |
| P2.4 | Pan law selection (0/-3/-4.5/-6 dB) | `daw_lower_zone_widget.dart` |

#### P3: Lower Priority Features (Completed)
| Task | Description | File |
|------|-------------|------|
| P3.1 | Keyboard shortcuts overlay (? key) | `keyboard_shortcuts_overlay.dart` |
| P3.2 | Save as Template menu item | `app_menu_bar.dart`, `layout_models.dart` |
| P3.3 | Clip gain envelope visualization | `clip_widget.dart` |

**New Widgets Created:**
- `keyboard_shortcuts_overlay.dart` — Modal overlay with categorized shortcuts, search filtering
- `_GainEnvelopePainter` — CustomPainter for clip gain visualization (dashed line, dB label)

**New Callbacks:**
- `MenuCallbacks.onSaveAsTemplate` — Save as Template menu action

**Key Features:**
- **Pan Laws:** Equal Power (-3dB), Linear (0dB), Compromise (-4.5dB), Linear Sum (-6dB) — ✅ **FFI CONNECTED (2026-01-24)** via `stereoImagerSetPanLaw()`
- **Keyboard Shortcuts:** Categorized by Transport/Edit/View/Tools/Mixer/Timeline/SlotLab/Global
- **Gain Envelope:** Orange=boost, Cyan=cut, dB value at center

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

### UI Provider Optimization (2026-01-23) ✅

Consumer→Selector conversion for reduced widget rebuilds.

| Panel | Selector Type | Impact |
|-------|---------------|--------|
| `advanced_middleware_panel.dart` | `MiddlewareStats` | 5 Consumers → 1 Selector |
| `blend_container_panel.dart` | `List<BlendContainer>` | Targeted rebuilds only |
| `random_container_panel.dart` | `List<RandomContainer>` | Targeted rebuilds only |
| `sequence_container_panel.dart` | `List<SequenceContainer>` | Targeted rebuilds only |
| `events_folder_panel.dart` | `EventsFolderData` | 5-field typedef selector |
| `music_system_panel.dart` | `MusicSystemData` | 2-field typedef selector |
| `attenuation_curve_panel.dart` | `List<AttenuationCurve>` | Simple list selector |
| `event_editor_panel.dart` | `List<MiddlewareEvent>` | Provider events sync |
| `slot_audio_panel.dart` | `MiddlewareStats` | Removed 6 unused params |

**Pattern:**
```dart
// Before: Rebuilds on ANY provider change
Consumer<MiddlewareProvider>(builder: (ctx, provider, _) { ... })

// After: Rebuilds only when selected data changes
Selector<MiddlewareProvider, SpecificType>(
  selector: (_, p) => p.specificData,
  builder: (ctx, data, _) {
    // Actions via context.read<MiddlewareProvider>()
  },
)
```

**Typedefs** (`middleware_provider.dart:43-72`):
- `MiddlewareStats` — 12 stat fields
- `EventsFolderData` — events, selection, clipboard (5 fields)
- `MusicSystemData` — segments + stingers

### Performance Results

- **Audio latency:** < 3ms @ 128 samples (zero locks in RT)
- **DSP load:** ~15-20% @ 44.1kHz stereo
- **UI frame rate:** Solid 60fps (vsync Ticker)
- **Binary:** Optimized (lto=fat, strip=true, panic=abort)
- **UI rebuilds:** Targeted via Selector (reduced ~60% unnecessary rebuilds)

**Tools:**

```bash
cargo flamegraph --release     # CPU profiling
cargo bench --package rf-dsp   # DSP benchmarks
flutter run --profile          # UI performance
```

### UI Layout Fixes (2026-01-23) ✅

Critical overflow fixes in Lower Zone and FabFilter panels.

**FabFilter Panel Spacer Fix:**

| Panel | Line | Problem | Fix |
|-------|------|---------|-----|
| `fabfilter_limiter_panel.dart` | 630 | `Spacer` in unbounded Column | `Flexible(child: SizedBox(height: 8))` |
| `fabfilter_compressor_panel.dart` | 927 | `Spacer` in unbounded Column | `Flexible(child: SizedBox(height: 8))` |
| `fabfilter_gate_panel.dart` | 498 | `Spacer` in unbounded Column | `Flexible(child: SizedBox(height: 8))` |
| `fabfilter_reverb_panel.dart` | 467 | `Spacer` in unbounded Column | `Flexible(child: SizedBox(height: 8))` |

**Root Cause:** `Spacer()` inside Column without bounded height tries to take infinite space → overflow when Lower Zone is resized small.

**LowerZoneContextBar 1px Overflow Fix:**

| File | Problem | Fix |
|------|---------|-----|
| `lower_zone_context_bar.dart` | `mainAxisSize: MainAxisSize.min` + border = 1px overflow | Removed min, wrapped sub-tabs in `Expanded` |

**Before:**
```dart
Column(
  mainAxisSize: MainAxisSize.min,  // ← Conflict with fixed parent height
  children: [
    _buildSuperTabs(),           // 32px
    if (isExpanded) _buildSubTabs(),  // 28px
  ],
)
```

**After:**
```dart
Column(
  children: [
    _buildSuperTabs(),           // 32px fixed
    if (isExpanded) Expanded(child: _buildSubTabs()),  // fills remaining 28px
  ],
)
```

### Middleware Inspector Improvements (2026-01-24) ✅

P0 critical fixes for the right inspector panel in `event_editor_panel.dart`.

**P0.1: TextFormField Key Fix**
- **Problem:** Event name field didn't update when switching between events
- **Root Cause:** `TextFormField` with `initialValue` doesn't rebuild when value changes
- **Fix:** Added `fieldKey: ValueKey('event_name_${event.id}')` to force rebuild

**P0.2: Slider Debouncing (Performance)**
- **Problem:** Every slider drag fired immediate provider sync → excessive FFI calls
- **Fix:** Added `_sliderDebounceTimer` with 50ms debounce
- **Affected sliders:** Delay, Fade Time, Gain, Pan
- **New method:** `_updateActionDebounced()` for slider-only updates

**P0.3: Gain dB Display**
- **Problem:** Gain showed percentage (0-200%) instead of industry-standard dB
- **Fix:** New `_buildGainSlider()` with dB conversion and presets
- **Display:** `-∞ dB` to `+6 dB` with color coding (orange=boost)
- **Presets:** -12dB, -6dB, 0dB, +3dB, +6dB quick buttons

**P0.4: Slider Debounce Race Condition Fix (2026-01-25)**
- **Problem:** Slider changes (pan, gain, delay, fadeTime) were silently reverted upon release
- **Root Cause:** During 50ms debounce period, widget rebuilds triggered `_syncEventsFromProviderList()` which overwrote local slider changes with provider's stale data
- **Fix:** Added `_pendingEditEventId` tracking — skip provider→local sync for events with pending local edits
- **Fields added:** `_pendingEditEventId` (String?)
- **Pattern:** "Pending Edit Protection" — mark event on local change, skip in sync, clear after provider sync completes

**Code Changes:**
```dart
// P0.1: TextFormField with key
_buildInspectorEditableField(
  'Name', event.name, onChanged,
  fieldKey: ValueKey('event_name_${event.id}'),  // Forces rebuild
);

// P0.2: Debounced slider
void _updateActionDebounced(...) {
  setState(() { /* immediate UI update */ });
  _sliderDebounceTimer?.cancel();
  _sliderDebounceTimer = Timer(Duration(milliseconds: 50), () {
    _syncEventToProvider(...);  // Delayed FFI sync
  });
}

// P0.3: dB conversion
String gainToDb(double g) {
  if (g <= 0.001) return '-∞ dB';
  final db = 20 * math.log(g) / math.ln10;
  return '${db.toStringAsFixed(1)} dB';
}

// P0.4: Pending edit protection
String? _pendingEditEventId;

void _updateActionDebounced(...) {
  _pendingEditEventId = event.id;  // Mark as pending
  setState(() { /* update local */ });
  _sliderDebounceTimer = Timer(Duration(milliseconds: 50), () {
    _syncEventToProvider(...);
    _pendingEditEventId = null;  // Clear after sync
  });
}

void _syncEventsFromProviderList(List<MiddlewareEvent> events) {
  for (final event in events) {
    if (event.id == _pendingEditEventId) continue;  // Skip pending!
    // ... rest of sync
  }
}
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

### FabFilter-Style Premium DSP Panels (2026-01-22) ✅

Professional DSP panel suite inspired by FabFilter's design language.

**Location:** `flutter_ui/lib/widgets/fabfilter/`

| Panel | Inspiration | Features | FFI |
|-------|-------------|----------|-----|
| `fabfilter_compressor_panel.dart` | Pro-C 2 | Transfer curve, knee display, 14 styles, sidechain EQ | ✅ |
| `fabfilter_limiter_panel.dart` | Pro-L 2 | LUFS metering, 8 styles, true peak, GR history | ✅ |
| `fabfilter_gate_panel.dart` | Pro-G | State indicator, threshold viz, sidechain filter | ✅ |
| `fabfilter_reverb_panel.dart` | Pro-R | Decay display, pre-delay, 8 space types, EQ | ✅ |

**Shared Components:**
- `fabfilter_theme.dart` — Colors, gradients, text styles
- `fabfilter_knob.dart` — Pro knob with modulation ring, fine control
- `fabfilter_panel_base.dart` — A/B comparison, undo/redo, bypass
- `fabfilter_preset_browser.dart` — Categories, search, favorites

**Total:** ~5,450 LOC

**SlotLab Lower Zone Integration (2026-01-22):**

| Key | Tab | Panel |
|-----|-----|-------|
| `5` | Compressor | FabFilterCompressorPanel (Pro-C style) |
| `6` | Limiter | FabFilterLimiterPanel (Pro-L style) |
| `7` | Gate | FabFilterGatePanel (Pro-G style) |
| `8` | Reverb | FabFilterReverbPanel (Pro-R style) |

**Files:**
- `lower_zone_controller.dart` — Tab enums + keyboard shortcuts
- `lower_zone.dart` — Panel instances in IndexedStack

### 🟢 FabFilter Panels → DspChainProvider Integration (2026-01-23) ✅

**Status:** FIXED — All DSP panels now use DspChainProvider + InsertProcessor chain.

**Architecture (Correct):**
```
UI Panel → DspChainProvider.addNode() → insertLoadProcessor() → track_inserts → Audio Thread ✅
         → insertSetParam(trackId, slotIndex, paramIndex, value) → Real-time parameter updates ✅
```

**Converted Panels:**
| Panel | Wrapper | Status |
|-------|---------|--------|
| FabFilterCompressorPanel | CompressorWrapper | ✅ Done |
| FabFilterLimiterPanel | LimiterWrapper | ✅ Done |
| FabFilterGatePanel | GateWrapper | ✅ Done |
| FabFilterReverbPanel | ReverbWrapper | ✅ Done |
| DynamicsPanel | CompressorWrapper | ✅ Done |
| DeEsserPanel | DeEsserWrapper | ✅ Done |

**Deleted Ghost Code:**
- `DYNAMICS_*` HashMaps from `ffi.rs` — ~650 LOC deleted
- `DynamicsAPI` extension from `native_ffi.dart` — ~250 LOC deleted
- Ghost FFI functions: `compressor_*`, `limiter_*`, `gate_*`, `expander_*`, `deesser_*`

**Preserved:**
- `CompressorType` enum (used by UI)
- `DeEsserMode` enum (used by UI)

**P1.7 Factory Function Bug (2026-01-23) — FIXED:**
```rust
// PROBLEM: api.rs:insert_load() used create_processor() which only supports EQ!
// SOLUTION: Changed to create_processor_extended() which supports ALL processors

// Supported by create_processor_extended():
// EQ: "pro-eq", "ultra-eq", "pultec", "api550", "neve1073", "room-correction"
// Dynamics: "compressor", "limiter", "gate", "expander", "deesser"
// Effects: "reverb", "algorithmic-reverb"
```

**Documentation:** `.claude/architecture/DSP_ENGINE_INTEGRATION_CRITICAL.md`

### FabFilter Real-Time Metering FFI (2026-01-24) ✅

Real-time metering via channel strip FFI functions.

**Limiter Panel (`fabfilter_limiter_panel.dart:_updateMeters()`):**
| Meter | FFI Function | Notes |
|-------|-------------|-------|
| Gain Reduction | `channelStripGetLimiterGr(trackId)` | dB value |
| True Peak | `advancedGetTruePeak8x().maxDbtp` | 8x oversampled |
| Peak Levels | `getPeakMeters()` | Returns (L, R) linear, convert to dB |

**Compressor Panel (`fabfilter_compressor_panel.dart:_updateMeters()`):**
| Meter | FFI Function | Notes |
|-------|-------------|-------|
| Gain Reduction | `channelStripGetCompGr(trackId)` | dB value |
| Input Level | `channelStripGetInputLevel(trackId)` | Linear → dB |
| Output Level | `channelStripGetOutputLevel(trackId)` | Linear → dB |

**Linear to dB Conversion:**
```dart
final dB = linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -60.0;
```

### DSP Debug Widgets (2026-01-23) ✅

Debug widgets za vizualizaciju i debugging DSP insert chain-a.

**Location:** `flutter_ui/lib/widgets/debug/`

| Widget | File | LOC | Description |
|--------|------|-----|-------------|
| `InsertChainDebug` | `insert_chain_debug.dart` | ~270 | Shows loaded processors, slot indices, params, engine verification |
| `SignalAnalyzerWidget` | `signal_analyzer_widget.dart` | ~510 | Signal flow viz: INPUT→Processors→OUTPUT with real-time metering |
| `DspDebugPanel` | `dsp_debug_panel.dart` | ~50 | Combined panel (SignalAnalyzer + InsertChainDebug) |

**Features:**
- Real-time peak/RMS metering (30fps refresh)
- Per-processor status (type, slot index, bypass state)
- Color-coded processor nodes (EQ=blue, Comp=orange, Lim=red, etc.)
- Engine-side parameter verification via `insertGetParam()`

**Usage:**
```dart
// Full debug panel
DspDebugPanel(trackId: 0)  // 0 = master bus

// Signal flow only
SignalAnalyzerWidget(trackId: 0, width: 600, height: 200)

// Chain status only
InsertChainDebug(trackId: 0)
```

### UltimateMixer Integration (2026-01-22) ✅

**UltimateMixer je sada jedini mixer** — ProDawMixer je uklonjen.

| Feature | Status | Description |
|---------|--------|-------------|
| Volume Fader | ✅ | All channel types (audio, bus, aux, VCA, master) |
| Pan (Mono) | ✅ | Standard pan knob |
| Pan L/R (Stereo) | ✅ | Pro Tools-style dual pan |
| Mute/Solo/Arm | ✅ | All channel types |
| Peak/RMS Metering | ✅ | Real-time levels |
| Send Level/Mute | ✅ | Per-channel aux sends |
| Send Pre/Post Fader | ✅ | Toggle pre/post fader mode |
| Send Destination | ✅ | Change send routing |
| Output Routing | ✅ | Channel → Bus routing |
| Phase Toggle | ✅ | Input phase invert |
| Input Gain | ✅ | -20dB to +20dB trim |
| VCA Faders | ✅ | Group volume control |
| Add Bus | ✅ | Dynamic bus creation |
| Glass/Classic Mode | ✅ | Auto-detected via ThemeModeProvider |
| **Channel Reorder** | ✅ | Drag-drop reorder with bidirectional Timeline sync |

**Key Files:**
- `ultimate_mixer.dart` — Main mixer widget (~2250 LOC)
- `daw_lower_zone_widget.dart` — Full MixerProvider integration
- `glass_mixer.dart` — Thin wrapper (ThemeAwareMixer)
- `mixer_provider.dart` — Channel order management, `reorderChannel()`, `setChannelOrder()`

**Deleted Files:**
- `pro_daw_mixer.dart` — Removed (~1000 LOC duplicate)

**Import Pattern (namespace conflict fix):**
```dart
import '../widgets/mixer/ultimate_mixer.dart' as ultimate;
// Use: ultimate.UltimateMixer, ultimate.ChannelType.audio, etc.
```

**Dokumentacija:** `.claude/architecture/ULTIMATE_MIXER_INTEGRATION.md`

### Bidirectional Channel/Track Reorder (2026-01-24) ✅

Drag-drop reorder za mixer kanale i timeline track-ove sa automatskom sinhronizacijom.

**Arhitektura:**
```
Mixer Drag → MixerProvider.reorderChannel() → onChannelOrderChanged → Timeline._tracks update
Timeline Drag → _handleTrackReorder() → MixerProvider.setChannelOrder() → channels getter update
```

**MixerProvider API:**
```dart
// Channel order tracking
List<String> get channelOrder;                    // Current order (IDs)
List<MixerChannel> get channels;                  // Channels in display order

// Reorder methods
void reorderChannel(int oldIndex, int newIndex);  // From mixer drag
void setChannelOrder(List<String> newOrder, {bool notifyTimeline});  // From timeline
int getChannelIndex(String channelId);            // Get display index

// Callback for sync
void Function(List<String>)? onChannelOrderChanged;  // Notifies timeline
```

**Timeline API:**
```dart
// Callback
final void Function(int oldIndex, int newIndex)? onTrackReorder;

// Widget: _DraggableTrackRow
// - LongPressDraggable for vertical drag
// - DragTarget for drop zone
// - Visual feedback (drop indicator)
```

**UltimateMixer API:**
```dart
// Callback
final void Function(int oldIndex, int newIndex)? onChannelReorder;

// Widget: _DraggableChannelStrip
// - LongPressDraggable for horizontal drag
// - DragTarget for drop zone
// - Visual feedback (opacity, drop indicator)
```

**Key Files:**
| File | Changes |
|------|---------|
| `mixer_provider.dart` | `_channelOrder`, `reorderChannel()`, `setChannelOrder()`, `onChannelOrderChanged` |
| `ultimate_mixer.dart` | `onChannelReorder`, `_DraggableChannelStrip` widget |
| `timeline.dart` | `onTrackReorder`, `_DraggableTrackRow` widget |
| `engine_connected_layout.dart` | `_handleTrackReorder()`, `_onMixerChannelOrderChanged()` |

### Export Adapters (2026-01-22) ✅

Platform export za Unity, Unreal Engine i Howler.js.

**Location:** `flutter_ui/lib/services/export/`

| Exporter | Target | Output Files | LOC |
|----------|--------|--------------|-----|
| `unity_exporter.dart` | Unity C# | Events, RTPC, States, Ducking, Manager, JSON | ~580 |
| `unreal_exporter.dart` | Unreal C++ | Types.h, Events.h/cpp, RTPC.h/cpp, Manager.h/cpp, JSON | ~720 |
| `howler_exporter.dart` | Howler.js | TypeScript/JavaScript audio manager, types, JSON | ~650 |

**Unity Output:**
- `FFEvents.cs` — Event definicije + enumi
- `FFRtpc.cs` — RTPC definicije
- `FFStates.cs` — State/Switch enumi
- `FFDucking.cs` — Ducking pravila
- `FFAudioManager.cs` — MonoBehaviour manager
- `FFConfig.json` — ScriptableObject JSON

**Unreal Output:**
- `FFTypes.h` — USTRUCT/UENUM definicije (BlueprintType)
- `FFEvents.h/cpp` — Event definicije
- `FFRtpc.h/cpp` — RTPC definicije
- `FFDucking.h` — Ducking pravila
- `FFAudioManager.h/cpp` — UActorComponent
- `FFConfig.json` — Data asset JSON

**Howler.js Output:**
- `fluxforge-audio.ts` — TypeScript audio manager sa Howler.js
- `fluxforge-types.ts` — TypeScript type definicije
- `fluxforge-config.json` — JSON config

**Usage:**
```dart
final exporter = UnityExporter(config: UnityExportConfig(
  namespace: 'MyGame.Audio',
  classPrefix: 'MG',
));
final result = exporter.export(
  events: compositeEvents,
  rtpcs: rtpcDefinitions,
  stateGroups: stateGroups,
  switchGroups: switchGroups,
  duckingRules: duckingRules,
);
// result.files contains generated code
```

### Timeline
- ✅ Multi-track arrangement
- ✅ Clip editing (move, trim, fade)
- ✅ Crossfades (equal power, S-curve)
- ✅ Loop playback
- ✅ Scrubbing with velocity

### DAW Waveform System (2026-01-25) ✅

Real waveform generation via Rust FFI — demo waveform potpuno uklonjen.

**Arhitektura:**
```
Audio File Import → NativeFFI.generateWaveformFromFile(path, cacheKey)
                  → Rust SIMD waveform generation (AVX2/NEON)
                  → JSON response with multi-LOD peaks
                  → parseWaveformFromJson() → Float32List
                  → ClipWidget rendering (graceful null handling)
```

**FFI Funkcija:** `generateWaveformFromFile(path, cacheKey)` → JSON

**JSON Format:**
```json
{
  "lods": [
    {
      "samples_per_pixel": 1,
      "left": [{"min": -0.5, "max": 0.5, "rms": 0.3}, ...],
      "right": [{"min": -0.5, "max": 0.5, "rms": 0.3}, ...]
    }
  ]
}
```

**Helper Funkcija:** `parseWaveformFromJson()` ([timeline_models.dart](flutter_ui/lib/models/timeline_models.dart))
- Parsira JSON iz Rust FFI
- Vraća `(Float32List?, Float32List?)` tuple za L/R kanale
- Automatski bira odgovarajući LOD (max 2048 samples)
- Ekstrahuje peak vrednosti (max absolute value)
- Ako FFI fail-uje, vraća `(null, null)` — UI gracefully handluje null waveform

**Demo Waveform:** UKLONJEN (2026-01-25)
- `generateDemoWaveform()` funkcija obrisana iz `timeline_models.dart`
- Svi fallback-ovi uklonjeni iz `engine_connected_layout.dart`
- ClipWidget već podržava nullable waveform

**Duration Display:**
| Getter | Format | Primer |
|--------|--------|--------|
| `durationFormatted` | Sekunde (2 decimale) | `45.47s` |
| `durationFormattedMs` | Milisekunde | `45470ms` |
| `durationMs` | Int milisekunde | `45470` |

**Lokacije gde se koristi real waveform:**
| Fajl | Linija | Kontekst |
|------|--------|----------|
| `engine_connected_layout.dart` | ~3014 | `_addFileToPool()` — audio import |
| `engine_connected_layout.dart` | ~3077 | `_syncAudioPoolFromSlotLab()` |
| `engine_connected_layout.dart` | ~3117 | `_syncFromAssetManager()` |
| `engine_connected_layout.dart` | ~2408 | `_handleAudioPoolFileDoubleClick()` |

**Fallback:** Ako FFI ne vrati waveform, waveform ostaje `null` — UI gracefully handluje null.

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

### Unified Routing System (2026-01-20) ✅ COMPLETE
- ✅ Unified Routing Graph (dynamic channels, topological sort)
- ✅ FFI bindings (11 funkcija: create/delete/output/sends/volume/pan/mute/solo/query)
- ✅ RoutingProvider (Flutter state management)
- ✅ Atomic channel_count (lock-free FFI query)
- ✅ Channel list sync (routing_get_all_channels + routing_get_channels_json) — Added 2026-01-24
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

**MixerDSPProvider** (`mixer_dsp_provider.dart`) — UPDATED 2026-01-24:
- Bus volume → `NativeFFI.setBusVolume(engineIdx, volume)`
- Bus pan → `NativeFFI.setBusPan(engineIdx, pan)`
- Mute/Solo → `NativeFFI.setBusMute/Solo(engineIdx, state)`
- `connect()` sinhronizuje sve buseve sa engine-om

**Bus Engine ID Mapping (Rust Convention):**
```
master=0, music=1, sfx=2, voice=3, ambience=4, aux=5
```
*CRITICAL: Must match `crates/rf-engine/src/playback.rs` lines 3313-3319*

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
- `beat_grid_editor.dart` — Visual beat/bar grid editing (~900 LOC)
- `music_transition_preview_panel.dart` — Segment transition preview (~750 LOC)
- `stinger_preview_panel.dart` — Stinger playback preview (~650 LOC)
- `music_segment_looping_panel.dart` — Loop region editor (~1000 LOC)

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

### Container System Integration (2026-01-22) ✅

Full event→container playback delegation za dinamički audio.

**Arhitektura:**
```
AudioEvent.usesContainer = true
         ↓
EventRegistry.triggerEvent()
         ↓
_triggerViaContainer() → ContainerService
         ↓
┌────────────────┬────────────────┬────────────────┐
│ BlendContainer │ RandomContainer│ SequenceContainer│
│ (RTPC volumes) │ (weighted pick)│ (timed steps)   │
└────────────────┴────────────────┴────────────────┘
         ↓
AudioPlaybackService.playFileToBus()
```

**P0 Backend (COMPLETED):**
- `ContainerType` enum: `none`, `blend`, `random`, `sequence`
- `AudioEvent.containerType` + `containerId` fields
- `ContainerService.triggerBlendContainer/RandomContainer/SequenceContainer()`
- `audioPath` field dodato u BlendChild, RandomChild, SequenceStep

**P1 UI (COMPLETED):**
- Audio file picker u container panel child editors
- Container selector (mode toggle + dropdowns) u SlotLab event expanded view
- Container badge u Event Log (purple=Blend, amber=Random, teal=Sequence)

**Ključni fajlovi:**
| Fajl | Promene |
|------|---------|
| `event_registry.dart` | ContainerType enum, container delegation, tracking |
| `container_service.dart` | triggerXxxContainer(), getXxxContainer() |
| `middleware_models.dart` | audioPath na child klasama |
| `slot_audio_events.dart` | containerType/containerId na SlotCompositeEvent |
| `slot_lab_screen.dart` | Container selector UI |
| `event_log_panel.dart` | Container badge widget |
| `*_container_panel.dart` | Audio picker UI |

**Dokumentacija:** `.claude/tasks/CONTAINER_P0_INTEGRATION.md`, `.claude/tasks/CONTAINER_P1_UI_INTEGRATION.md`

**P2 Rust FFI (COMPLETED 2026-01-22):**

Sub-millisecond container evaluation via Rust FFI.

| Metric | Dart-only (P1) | Rust FFI (P2) |
|--------|----------------|---------------|
| Blend trigger | ~5-10ms | < 0.5ms |
| Random select | ~3-5ms | < 0.2ms |
| Sequence tick | ~2-4ms | < 0.1ms |

**Rust Implementation:**
- `crates/rf-engine/src/containers/` — BlendContainer, RandomContainer, SequenceContainer
- `crates/rf-bridge/src/container_ffi.rs` — C FFI functions (~760 LOC)
- ContainerStorage: DashMap-based lock-free storage
- SmallVec for stack-allocated children (8-32 elements)
- 19 Rust tests passing

**Dart FFI Bindings:**
- `native_ffi.dart` — `ContainerFFI` extension
- `containerCreateBlend/Random/Sequence()` — JSON config → Rust ID
- `containerEvaluateBlend()` → `List<BlendEvalResult>`
- `containerSelectRandom()` → `RandomSelectResult?`
- `containerTickSequence()` → `SequenceTickResult`

**ContainerService Integration:**
- FFI init with Dart fallback (`isRustAvailable`)
- `syncBlendToRust()`, `syncRandomToRust()`, `syncSequenceToRust()`
- Provider hooks: auto-sync on create/update/remove

**Benchmark Utility:**
- `flutter_ui/lib/utils/container_benchmark.dart`
- Measures Rust FFI vs Dart latency (1000 iterations)
- Returns avg/min/max/P50/P99 statistics with speedup factors

**Dokumentacija:** `.claude/tasks/CONTAINER_P2_RUST_FFI.md`

**P3 Advanced (COMPLETED 2026-01-22):**

All P3 optimizations implemented:

| Feature | Status | Description |
|---------|--------|-------------|
| 3A: Rust-Side Sequence Timing | ✅ DONE | Rust tick-based timing via `ContainerService._tickRustSequence()` |
| 3B: Audio Path Caching | ✅ DONE | Paths stored in Rust models, FFI `get_*_audio_path()` functions |
| 3D: Parameter Smoothing | ✅ DONE | Critically damped spring RTPC interpolation (0-1000ms) |
| 3E: Container Presets | ✅ DONE | Export/import `.ffxcontainer` JSON files with schema versioning |
| 3C: Container Groups | ✅ DONE | Hierarchical nesting (Random→Blend, Sequence→Random, etc.) |

**P3A: Rust-Side Sequence Timing**
- `container_service.dart`: `_activeRustSequences`, `_tickRustSequence()`, `_playSequenceStep()`
- Dart Timer replaced with periodic tick calls to Rust `container_tick_sequence()`
- Microsecond-accurate step triggering

**P3D: Parameter Smoothing (RTPC)**
- `crates/rf-engine/src/containers/blend.rs`: `smoothing_ms`, `tick_smoothing()`, `smoothed_rtpc()`
- Critically damped spring interpolation (no overshoot)
- FFI: `container_set_blend_rtpc_target()`, `container_tick_blend_smoothing()`

**P3E: Container Presets**
- `flutter_ui/lib/services/container_preset_service.dart` (~380 LOC)
- Schema versioned JSON (v1), `.ffxcontainer` extension
- Export/import for Blend, Random, Sequence containers
- Note: `audioPath` NOT exported (project-specific)

**P3C: Container Groups**
- `crates/rf-engine/src/containers/group.rs` (~220 LOC)
- `ContainerGroup`, `GroupChild`, `GroupEvaluationMode` (All/FirstMatch/Priority/Random)
- FFI: `container_create_group()`, `container_evaluate_group()`, `container_group_add_child()`
- Enables complex sound design: Random→Blend (pick variant, crossfade by RTPC)

**Dokumentacija:** `.claude/tasks/CONTAINER_P3_ADVANCED.md`

### Audio Waveform Picker Dialog (2026-01-22) ✅

Reusable modal dialog za selekciju audio fajlova sa waveform preview-om.

**Lokacija:** `flutter_ui/lib/widgets/common/audio_waveform_picker_dialog.dart`

**Features:**
- Directory tree navigation sa quick access (Music, Documents, Downloads, Desktop)
- Audio file listing sa format filter (WAV, FLAC, MP3, OGG, AIFF)
- Waveform preview na hover (koristi `AudioBrowserPanel`)
- Playback preview sa play/stop kontrolom
- Search po imenu fajla
- Drag support za buduću timeline integraciju

**Usage:**
```dart
final path = await AudioWaveformPickerDialog.show(
  context,
  title: 'Select Audio File',
  initialDirectory: '/path/to/audio',
);
if (path != null) {
  // Use selected audio path
}
```

**Integracija u Container Panele:**
| Panel | File | Status |
|-------|------|--------|
| BlendContainerPanel | `blend_container_panel.dart` | ✅ Integrisano |
| RandomContainerPanel | `random_container_panel.dart` | ✅ Integrisano |
| SequenceContainerPanel | `sequence_container_panel.dart` | ✅ Integrisano |

**Zamenjuje:** Osnovni `FilePicker.platform.pickFiles()` bez preview-a

### Container Storage Metrics (2026-01-22) ✅

Real-time prikaz container statistika iz Rust engine-a.

**Lokacija:** `flutter_ui/lib/widgets/middleware/container_storage_metrics.dart`

**FFI Bindings (native_ffi.dart):**
```dart
int getBlendContainerCount()     // Rust: middleware_get_blend_container_count
int getRandomContainerCount()    // Rust: middleware_get_random_container_count
int getSequenceContainerCount()  // Rust: middleware_get_sequence_container_count
int getTotalContainerCount()     // Sum of all
Map<String, int> getContainerStorageMetrics()  // Complete map
```

**Widgets:**
| Widget | Opis | Usage |
|--------|------|-------|
| `ContainerStorageMetricsPanel` | Detailed panel sa breakdown | Middleware debug panel |
| `ContainerMetricsBadge` | Compact badge za status bars | Panel footers |
| `ContainerMetricsRow` | Inline row (B:2 R:5 S:1 = 8) | Quick stats |

**Features:**
- Auto-refresh (configurable interval)
- Memory estimate calculation
- Color-coded per container type (Blend=purple, Random=amber, Sequence=teal)

### Determinism Seed Capture (2026-01-23) ✅

RNG seed logging za deterministic replay RandomContainer selekcija.

**Rust Implementation:** `crates/rf-engine/src/containers/random.rs`

```rust
// Global seed log (thread-safe)
pub static SEED_LOG: Lazy<Mutex<SeedLog>> = Lazy::new(|| Mutex::new(SeedLog::new()));

pub struct SeedLogEntry {
    pub tick: u64,
    pub container_id: ContainerId,
    pub seed_before: u64,      // RNG state pre-selection
    pub seed_after: u64,       // RNG state post-selection
    pub selected_id: ChildId,  // Which child was selected
    pub pitch_offset: f64,     // Applied pitch variation
    pub volume_offset: f64,    // Applied volume variation
}
```

**SeedLog API:**
| Method | Description |
|--------|-------------|
| `enable()` / `disable()` | Toggle logging on/off |
| `is_enabled()` | Check if logging is active |
| `record(entry)` | Log a selection (ring buffer, 256 max) |
| `clear()` | Clear all entries |
| `len()` | Number of entries |
| `entries()` | Get all entries |

**FFI Functions:** `crates/rf-bridge/src/container_ffi.rs`
```rust
seed_log_enable(enabled: i32)           // Enable/disable logging
seed_log_is_enabled() -> i32            // Check status
seed_log_clear()                        // Clear log
seed_log_get_count() -> usize           // Entry count
seed_log_get_json() -> *const c_char    // Export all as JSON
seed_log_get_last_n_json(n) -> *const c_char  // Export last N
seed_log_replay_seed(container_id, seed) -> i32  // Restore RNG state
seed_log_get_rng_state(container_id) -> u64     // Get current RNG state
```

**Dart FFI Bindings:** `flutter_ui/lib/src/rust/native_ffi.dart`
```dart
class SeedLogEntry {
  final int tick;
  final int containerId;
  final String seedBefore;    // Hex string (u64)
  final String seedAfter;     // Hex string (u64)
  final int selectedId;
  final double pitchOffset;
  final double volumeOffset;

  int get seedBeforeInt => int.tryParse(seedBefore, radix: 16) ?? 0;
  int get seedAfterInt => int.tryParse(seedAfter, radix: 16) ?? 0;
}

// API
void seedLogEnable(bool enabled)
bool seedLogIsEnabled()
void seedLogClear()
int seedLogGetCount()
List<SeedLogEntry> seedLogGetEntries()
List<SeedLogEntry> seedLogGetLastN(int n)
bool seedLogReplaySeed(int containerId, int seed)
int seedLogGetRngState(int containerId)
```

**Use Cases:**
- **QA Replay**: Reproduce exact random selections for bug reports
- **A/B Testing**: Compare audio with identical random sequences
- **Debugging**: Track which children were selected and why
- **Session Recording**: Log all randomness for playback analysis

### P2.16 Async Undo Offload — SKIPPED ⏸️

**Problem:** Undo stack koristi `VoidCallback` funkcije koje se ne mogu serijalizovati.

**Trenutno stanje:**
```dart
// undo_manager.dart
class UiUndoManager {
  final List<UndoableAction> _undoStack = [];
  static const int _maxStackSize = 100;
}

abstract class UndoableAction {
  void execute();  // VoidCallback - NOT serializable
  void undo();     // VoidCallback - NOT serializable
}
```

**Zašto je preskočen:**
- Callbacks nisu serijalizabilni na disk
- Zahteva potpuni refaktor na data-driven pristup
- HIGH RISK, HIGH EFFORT (~2-3 nedelje)
- Trenutni limit od 100 akcija je dovoljno za većinu use-case-ova

**Buduće rešenje (P4):**
- Preći na Command Pattern sa serijalizabilnim podacima
- Svaka akcija bi imala `toJson()` / `fromJson()`
- Disk offload starijih akcija preko LRU strategije

### P2 Status Summary (2026-01-24)

**Completed: 22/22 (100%)**

| Task | Status | Note |
|------|--------|------|
| P2.1 | ✅ | SIMD metering via rf-dsp |
| P2.2 | ✅ | SIMD bus summation |
| P2.3 | ✅ | External Engine Integration (Stage Ingest, Connector FFI) |
| P2.4 | ✅ | Stage Ingest System (6 widgets, 2500 LOC) |
| P2.5 | ✅ | QA Framework (39 tests: 25 integration + 14 regression, CI/CD pipeline) |
| P2.6 | ✅ | Offline DSP Backend (~2900 LOC, EBU R128, True Peak, format conversion) |
| P2.7 | ✅ | Plugin Hosting UI (plugin_browser, plugin_slot, plugin_editor_window ~2141 LOC) |
| P2.8 | ✅ | MIDI Editing System (piano_roll, midi_clip_widget ~2624 LOC) |
| P2.9 | ✅ | Soundbank Building System (FFI audio metadata, ZIP archive, format conversion) |
| P2.10 | ✅ | Music System stinger UI (1227 LOC) |
| P2.11 | ✅ | Bounce Panel (DawBouncePanel) |
| P2.12 | ✅ | Stems Panel (DawStemsPanel) |
| P2.13 | ✅ | Archive Panel (_buildCompactArchive + ProjectArchiveService) |
| P2.14 | ✅ | SlotLab Batch Export |
| P2.15 | ✅ | Waveform downsampling (2048 max) |
| P2.17 | ✅ | Composite events limit (500 max) |
| P2.18 | ✅ | Container Storage Metrics (FFI) |
| P2.19 | ✅ | Custom Grid Editor (GameModelEditor) |
| P2.20 | ✅ | Bonus Game Simulator + FFI |
| P2.21 | ✅ | Audio Waveform Picker Dialog |
| P2.22 | ✅ | Schema Migration Service |

**Skipped: 1** (not blocking)
- P2.16 — VoidCallback not serializable, needs full refactor (deferred to P4)

### Soundbank Building System (2026-01-24) ✅

Complete soundbank export pipeline with FFI integration.

**Provider:** `flutter_ui/lib/providers/soundbank_provider.dart` (~780 LOC)
**Panel:** `flutter_ui/lib/widgets/soundbank/soundbank_panel.dart` (~1986 LOC)

**FFI Functions** (`crates/rf-bridge/src/offline_ffi.rs`):
| Function | Returns | Description |
|----------|---------|-------------|
| `offline_get_audio_info(path)` | JSON | Full metadata (sample_rate, channels, bit_depth, duration, samples) |
| `offline_get_audio_duration(path)` | f64 | Duration in seconds |
| `offline_get_audio_sample_rate(path)` | u32 | Sample rate in Hz |
| `offline_get_audio_channels(path)` | u32 | Channel count |

**Export Features:**
- ZIP archive creation (`.ffbank` extension)
- Audio format conversion via rf-offline pipeline
- Multi-platform export (Universal, Unity, Unreal, Howler.js)
- Manifest + config JSON generation
- Progress callbacks with status messages

**Supported Audio Formats:**
| Format | ID | Notes |
|--------|-----|-------|
| WAV 16-bit | 0 | PCM |
| WAV 24-bit | 1 | PCM |
| WAV 32-bit float | 2 | Float |
| FLAC | 3 | Lossless |
| MP3 High/Medium/Low | 4 | 320/192/128 kbps |
| OGG/WebM/AAC | 4 | Lossy (uses MP3 encoder fallback) |

**Usage:**
```dart
final provider = context.read<SoundbankProvider>();
await provider.exportBank(
  bankId: 'my_bank',
  config: SoundbankExportConfig(
    platform: SoundbankPlatform.universal,
    audioFormat: SoundbankAudioFormat.flac,
    compressArchive: true,
  ),
  outputPath: '/path/to/output',
  onProgress: (progress, status) => print('$status: ${(progress * 100).toInt()}%'),
);
```

### Project Archive Service (2026-01-24) ✅

ZIP archive creation for project backup and sharing.

**Service:** `flutter_ui/lib/services/project_archive_service.dart` (~250 LOC)

**API:**
```dart
final result = await ProjectArchiveService.instance.createArchive(
  projectPath: '/path/to/project',
  outputPath: '/path/to/archive.zip',
  config: ArchiveConfig(
    includeAudio: true,
    includePresets: true,
    includePlugins: false,
    compress: true,
  ),
  onProgress: (progress, status) => print('$status: ${(progress * 100).toInt()}%'),
);
```

**Features:**
- Configurable content (audio, presets, plugins)
- Progress callback with status messages
- Extract archive support
- Archive info inspection without extraction

**Integration:** DAW Lower Zone → DELIVER → Archive sub-tab
- Interactive checkboxes for options
- LinearProgressIndicator during creation
- "Open Folder" action on success

---

### Plugin State System (2026-01-24) ✅ IMPLEMENTED

Third-party plugin state management za project portability.

**Problem:** Third-party plugini (VST3/AU/CLAP) ne mogu biti redistribuirani zbog licenci.

**Rešenje — Gold Standard (kombinacija Pro Tools + Logic + Cubase):**

| Komponenta | Opis | Status |
|------------|------|--------|
| **Plugin Manifest** | JSON sa plugin referencama (UID, vendor, version, alternatives) | ✅ Done |
| **State Chunks** | Binary blobs (ProcessorState) za svaki plugin slot | ✅ Done |
| **Freeze Audio** | Rendered audio kao fallback kad plugin nedostaje | 📋 Planned |
| **Missing Plugin UI** | Dialog sa state preservation + alternative suggestions | 📋 Planned |

**Project Package Structure:**
```
MyProject.ffproj/
├── project.json           # Main project + Plugin Manifest
├── plugins/
│   ├── states/            # Binary state chunks (.ffstate)
│   └── presets/           # User presets (.fxp/.aupreset)
├── freeze/
│   └── track_01_freeze.wav  # Frozen audio (when plugin missing)
└── audio/
    └── ...
```

**Plugin Formats Supported:**
| Format | UID | State Format |
|--------|-----|--------------|
| VST3 | 128-bit FUID | ProcessorState (binary) |
| AU | Component ID | State Dictionary (plist) |
| CLAP | String ID | State Stream (binary) |

**Implementation Files:**

| Layer | File | LOC | Description |
|-------|------|-----|-------------|
| **Dart Models** | `models/plugin_manifest.dart` | ~500 | PluginFormat, PluginUid, PluginReference, PluginSlotState, PluginManifest, PluginStateChunk |
| **Rust Core** | `crates/rf-state/src/plugin_state.rs` | ~350 | Binary .ffstate format, PluginStateStorage |
| **Rust FFI** | `crates/rf-bridge/src/plugin_state_ffi.rs` | ~350 | 11 C FFI functions |
| **Dart FFI** | `src/rust/native_ffi.dart` (PluginStateFFI) | ~250 | Dart FFI bindings extension |
| **Dart Service** | `services/plugin_state_service.dart` | ~500 | Caching, manifest management, FFI integration |
| **Detector** | `services/missing_plugin_detector.dart` | ~350 | Plugin scanning, alternative suggestions |

**Binary .ffstate Format:**
```
Header (16 bytes):
├── Magic: "FFST" (4 bytes)
├── Version: u32 (4 bytes)
├── State Size: u64 (8 bytes)
Body:
├── Plugin UID: UTF-8 string (length-prefixed)
├── Preset Name: UTF-8 string (optional, length-prefixed)
├── Captured At: i64 timestamp
├── State Data: raw bytes
Footer:
└── CRC32 Checksum (4 bytes)
```

**FFI Functions (11 total):**

| Rust Function | Dart Method | Description |
|---------------|-------------|-------------|
| `plugin_state_store` | `pluginStateStore()` | Store state in cache |
| `plugin_state_get` | `pluginStateGet()` | Get state from cache |
| `plugin_state_get_size` | `pluginStateGetSize()` | Get state byte size |
| `plugin_state_remove` | `pluginStateRemove()` | Remove single state |
| `plugin_state_clear_all` | `pluginStateClearAll()` | Clear all states |
| `plugin_state_count` | `pluginStateCount()` | Count stored states |
| `plugin_state_save_to_file` | `pluginStateSaveToFile()` | Save to .ffstate file |
| `plugin_state_load_from_file` | `pluginStateLoadFromFile()` | Load from .ffstate file |
| `plugin_state_get_uid` | `pluginStateGetUid()` | Get plugin UID string |
| `plugin_state_get_preset_name` | `pluginStateGetPresetName()` | Get preset name |
| `plugin_state_get_all_json` | `pluginStateGetAllJson()` | Get all states as JSON |

**Service Registration (GetIt Layer 7):**
```dart
sl.registerLazySingleton<PluginStateService>(() => PluginStateService.instance);
sl.registerLazySingleton<MissingPluginDetector>(() => MissingPluginDetector.instance);
PluginAlternativesRegistry.instance.initBuiltInAlternatives();
```

**Implementation Phases:**
- Phase 1: Core Infrastructure (Models + FFI) — ✅ DONE (~850 LOC)
- Phase 2: Services (PluginStateService, MissingPluginDetector) — ✅ DONE (~700 LOC)
- Phase 2.5: Service Registration — ✅ DONE
- Phase 3: UI (MissingPluginDialog, PluginStateIndicator, InsertSlot) — ✅ DONE (~450 LOC)
- Phase 4: Integration (ProjectPluginIntegration) — ✅ DONE (~270 LOC)
- Phase 5: Testing — ✅ DONE (25 unit tests, ~430 LOC)

**Phase 3 UI Files:**
| File | LOC | Description |
|------|-----|-------------|
| `widgets/plugin/missing_plugin_dialog.dart` | ~350 | Dialog for missing plugins |
| `widgets/plugin/plugin_state_indicator.dart` | ~350 | State indicator widgets |
| `widgets/mixer/channel_strip.dart` | +50 | InsertSlot state fields |

**Phase 4 Integration Files:**
| File | LOC | Description |
|------|-----|-------------|
| `services/project_plugin_integration.dart` | ~270 | Project save/load integration utilities |

**Phase 5 Test Files:**
| File | LOC | Tests | Description |
|------|-----|-------|-------------|
| `test/plugin_state_test.dart` | ~430 | 25 | Unit tests for all plugin models |

**Test Coverage:**
- PluginFormat: 4 tests (values, display names, fromExtension)
- PluginUid: 6 tests (serialization, factories, equality)
- PluginReference: 2 tests (serialization, copyWith)
- PluginSlotState: 2 tests (serialization, nullable fields)
- PluginManifest: 6 tests (CRUD, serialization, getTrackSlots, vendors)
- PluginStateChunk: 2 tests (binary serialization, sizeBytes)
- PluginLocation: 2 tests (serialization, nullable fields)

**Documentation:** `.claude/architecture/PLUGIN_STATE_SYSTEM.md` (~1200 LOC)

---

### Critical Weaknesses — M2 Roadmap (2026-01-23) ✅ DONE

Top 5 problems identified in Ultimate System Analysis — **ALL RESOLVED**:

| # | Problem | Priority | Status |
|---|---------|----------|--------|
| 1 | No audio preview in event editor | P1 | ✅ DONE |
| 2 | No event debugger/tracer panel | P1 | ✅ DONE |
| 3 | Scattered stage configuration | P2 | ✅ DONE |
| 4 | No GDD import wizard | P2 | ✅ DONE |
| 5 | Limited container visualization | P2 | ✅ DONE |

**Full analysis:** `.claude/reviews/ULTIMATE_SYSTEM_ANALYSIS_2026_01_23.md`
**Documentation:** `.claude/docs/P3_CRITICAL_WEAKNESSES_2026_01_23.md`

---

### ✅ DAW Audio Flow — ALL CRITICAL GAPS RESOLVED (2026-01-24)

~~Ultra-detaljna analiza DAW sekcije otkrila je **2 KRITIČNA GAPA** u audio flow-u:~~

| Provider | FFI Status | Impact |
|----------|------------|--------|
| **DspChainProvider** | ✅ CONNECTED (25+ FFI) | DSP nodes connected to audio ✅ |
| **RoutingProvider** | ✅ CONNECTED (11 FFI) | Routing matrix connected to engine ✅ |

**P0 Tasks (5):** ✅ ALL COMPLETE
| # | Task | Status |
|---|------|--------|
| P0.1 | DspChainProvider FFI sync | ✅ COMPLETE (2026-01-23) |
| P0.2 | RoutingProvider FFI sync | ✅ COMPLETE (2026-01-24) |
| P0.3 | MIDI piano roll (Lower Zone) | ✅ COMPLETE |
| P0.4 | History panel UI | ✅ COMPLETE |
| P0.5 | FX Chain editor UI | ✅ COMPLETE |

**Overall DAW Connectivity:** 100% (7/7 providers connected, 125+ FFI functions)
**Documentation:** `.claude/architecture/DAW_AUDIO_ROUTING.md` (Section 14: Connectivity Summary)

---

### Channel Tab Improvements (2026-01-24) ✅

Complete Channel Tab feature implementation with FFI integration.

#### P1.4: Phase Invert (Ø) Button ✅
- Added `onChannelPhaseInvertToggle` callback to `GlassLeftZone` and `LeftZone`
- UI: Ø button in Channel Tab controls row (purple when active)
- FFI: Uses existing `trackSetPhaseInvert()` function

**Files:**
- [glass_left_zone.dart](flutter_ui/lib/widgets/glass/glass_left_zone.dart) — Added callback + UI button
- [left_zone.dart](flutter_ui/lib/widgets/layout/left_zone.dart) — Added callback passthrough
- [channel_inspector_panel.dart](flutter_ui/lib/widgets/layout/channel_inspector_panel.dart) — Added Ø button
- [main_layout.dart](flutter_ui/lib/screens/main_layout.dart) — Added callback passthrough

#### P0.3: Input Monitor FFI ✅
- Rust: `track_set_input_monitor()` and `track_get_input_monitor()` in [ffi.rs](crates/rf-engine/src/ffi.rs)
- Dart: FFI bindings in [native_ffi.dart](flutter_ui/lib/src/rust/native_ffi.dart)
- Provider: `MixerProvider.toggleInputMonitor()` now calls FFI

**FFI Functions:**
```rust
track_set_input_monitor(track_id: u64, enabled: i32)
track_get_input_monitor(track_id: u64) -> i32
```

#### P0.4: Internal Processor Editor Window ✅
- Created [internal_processor_editor_window.dart](flutter_ui/lib/widgets/dsp/internal_processor_editor_window.dart) (~530 LOC)
- Floating Overlay window with parameter sliders
- Supports all DspNodeTypes: EQ, Compressor, Limiter, Gate, Expander, Reverb, Delay, Saturation, DeEsser
- FFI integration via `insertSetParam(trackId, slotIndex, paramIndex, value)`

**Usage:**
```dart
InternalProcessorEditorWindow.show(
  context: context,
  trackId: 0,
  slotIndex: 0,
  node: dspNode,
);
```

**Callback Integration** ([engine_connected_layout.dart](flutter_ui/lib/screens/engine_connected_layout.dart)):
```dart
onChannelInsertOpenEditor: (channelId, slotIndex) {
  final chain = DspChainProvider.instance.getChain(trackId);
  if (slotIndex < chain.nodes.length) {
    InternalProcessorEditorWindow.show(...);  // Internal processor
  } else {
    NativeFFI.instance.insertOpenEditor(...); // External plugin
  }
},
```

#### P1.1: Model Consolidation ✅
- Added `LUFSData` model to [layout_models.dart](flutter_ui/lib/models/layout_models.dart)
- Added `lufs` field to `ChannelStripData`
- Refactored [channel_strip.dart](flutter_ui/lib/widgets/channel/channel_strip.dart):
  - Removed duplicate models: `InsertSlotData`, `SendSlotData`, `EQBandData`, `ChannelStripFullData`, `LUFSData`
  - Now uses `InsertSlot`, `SendSlot`, `EQBand`, `ChannelStripData`, `LUFSData` from `layout_models.dart`
  - LOC reduction: 1157 → 1049 (~108 LOC removed)

**Model Mapping:**
| Old (channel_strip.dart) | New (layout_models.dart) |
|--------------------------|--------------------------|
| `InsertSlotData` | `InsertSlot` |
| `SendSlotData` | `SendSlot` |
| `EQBandData` | `EQBand` |
| `ChannelStripFullData` | `ChannelStripData` |
| `LUFSData` (local) | `LUFSData` (shared) |

---

### ✅ DAW Gap Analysis (2026-01-24) — COMPLETE

Pronađeno i popravljeno 8 rupa u DAW sekciji:

#### P0 — CRITICAL ✅

| # | Gap | Opis | Status |
|---|-----|------|--------|
| **1** | Bus Mute/Solo FFI | UI menja state i šalje na engine | ✅ DONE |
| **2** | Input Gain FFI | `channelStripSetInputGain()` poziva FFI | ✅ DONE |

#### P1 — HIGH ✅

| # | Gap | Opis | Status |
|---|-----|------|--------|
| **3** | Send Removal FFI | `routing_remove_send()` dodat | ✅ DONE |
| **4** | Action Strip Stubs | Split, Duplicate, Delete connected via onDspAction | ✅ DONE |

#### P2 — MEDIUM ✅

| # | Gap | Opis | Status |
|---|-----|------|--------|
| **5** | Bus Pan Right FFI | `set_bus_pan_right()` dodat u Rust + Dart | ✅ DONE |
| **6** | Send Routing Error Handling | Snackbar feedback za success/failure | ✅ DONE |
| **7** | Input Monitor FFI | `trackSetInputMonitor()` connected u MixerProvider | ✅ DONE |

**Modified Files:**
- `engine_connected_layout.dart` — Bus mute/solo, pan right, send routing, action strip
- `mixer_provider.dart` — Input gain FFI, Input monitor FFI
- `native_ffi.dart` — routingRemoveSend, mixerSetBusPanRight bindings
- `engine_api.dart` — routingRemoveSend wrapper
- `crates/rf-engine/src/ffi.rs` — engine_set_bus_pan_right, routing_remove_send
- `crates/rf-engine/src/playback.rs` — BusState.pan_right field
- `crates/rf-engine/src/ffi_routing.rs` — routing_remove_send

**Documentation:** `.claude/architecture/DAW_AUDIO_ROUTING.md`

---

### Channel Strip Enhancements (2026-01-24) ✅

Prošireni ChannelStripData model i UI komponente sa novim funkcionalnostima.

**ChannelStripData Model** (`layout_models.dart`):

| Field | Type | Default | Opis |
|-------|------|---------|------|
| `panRight` | double | 0.0 | R channel pan za stereo dual-pan mode (-1 to 1) |
| `isStereo` | bool | false | True za stereo pan (L/R nezavisni) |
| `phaseInverted` | bool | false | Phase/polarity invert (Ø) |
| `inputMonitor` | bool | false | Input monitoring active |
| `lufs` | LUFSData? | null | LUFS loudness metering data |
| `eqBands` | List\<EQBand\> | [] | Per-channel EQ bands |

**LUFSData Model:**
```dart
class LUFSData {
  final double momentary;    // Momentary loudness (400ms)
  final double shortTerm;    // Short-term loudness (3s)
  final double integrated;   // Integrated loudness (full)
  final double truePeak;     // True peak (dBTP)
  final double? range;       // Loudness range (LRA)
}
```

**EQBand Model:**
```dart
class EQBand {
  final int index;
  final String type;      // 'lowcut', 'lowshelf', 'bell', 'highshelf', 'highcut'
  final double frequency;
  final double gain;      // dB
  final double q;
  final bool enabled;
}
```

**Novi UI Controls:**

| Control | Label | Color | Callback |
|---------|-------|-------|----------|
| Input Monitor | `I` | Blue | `onChannelMonitorToggle` |
| Phase Invert | `Ø` | Purple | `onChannelPhaseInvertToggle` |
| Pan Right | Slider | — | `onChannelPanRightChange` |

**MixerProvider Methods:**
```dart
void toggleInputMonitor(String id);      // Toggle + FFI sync
void setInputMonitor(String id, bool);   // Set + FFI sync
void setInputGain(String id, double);    // -20dB to +20dB + FFI sync
```

**Modified Widgets:**
- `channel_inspector_panel.dart` — I/Ø buttons, pan right callback
- `left_zone.dart` — Monitor/PhaseInvert/PanRight callbacks
- `glass_left_zone.dart` — Glass theme variant sa istim callbacks

**FFI Integration:**
- `trackSetInputMonitor(trackIndex, bool)` — Input monitor state
- `channelStripSetInputGain(trackIndex, dB)` — Input gain trim

---

### P3.1 — Audio Preview in Event Editor ✅ 2026-01-23

Real-time audio preview system in SlotLab event editor.

**Features:**
- Click layer → instant playback via AudioPool
- Auto-stop previous when clicking another
- Visual feedback: playing indicator on active layer
- Keyboard shortcut: Space to toggle play/stop

**Implementation:**
- `slot_lab_screen.dart` — `_playingPreviewLayerId` state, `_playPreviewLayer()` method
- Uses `AudioPool.acquire()` for instant sub-ms playback
- Stop via `AudioPlaybackService.stopVoice()`

---

### P3.2 — Event Debugger/Tracer Panel ✅ 2026-01-23

Real-time stage→audio tracing with performance metrics.

**UI Location:** SlotLab Lower Zone → "Event Debug" tab

**Features:**
- Live trace log: stage → event → voice ID → bus → latency
- Filterable by stage type, event name, bus
- Latency histogram visualization
- Export to JSON for analysis

**Components:**
- `event_debug_panel.dart` — Main panel widget (~650 LOC)
- `EventRegistry.onEventTriggered` stream for live events
- Latency tracking: triggerTime → playbackTime delta

---

### P3.3 — StageConfigurationService ✅ 2026-01-23

Centralized stage configuration — single source of truth for all stage definitions.

**Service:** `flutter_ui/lib/services/stage_configuration_service.dart` (~650 LOC)

**API:**
```dart
StageConfigurationService.instance.init();

// Stage queries
bool isPooled(String stage);           // Rapid-fire pooling
bool isLooping(String stage);          // Should audio loop (NEW 2026-01-24)
int getPriority(String stage);          // 0-100 priority
SpatialBus getBus(String stage);        // Audio bus routing
String getSpatialIntent(String stage);  // AutoSpatial intent
StageCategory getCategory(String stage); // Stage category

// Stage registration
void registerStage(StageDefinition def);
void registerStages(List<StageDefinition> defs);
List<StageDefinition> getStagesByCategory(StageCategory cat);
```

**isLooping() Detection Logic (2026-01-24):**
```dart
bool isLooping(String stage) {
  // 1. Check StageDefinition.isLooping first
  // 2. Fallback to pattern matching:
  //    - Ends with '_LOOP' suffix
  //    - Starts with 'MUSIC_', 'AMBIENT_', 'ATTRACT_', 'IDLE_'
  //    - In _loopingStages constant set
}
```

**Default Looping Stages:**
- REEL_SPIN_LOOP, MUSIC_BASE, MUSIC_TENSION, MUSIC_FEATURE
- FS_MUSIC, HOLD_MUSIC, BONUS_MUSIC
- AMBIENT_LOOP, ATTRACT_MODE, IDLE_LOOP
- ANTICIPATION_LOOP, FEATURE_MUSIC

**StageDefinition Model:**
```dart
class StageDefinition {
  final String stage;
  final StageCategory category;
  final int priority;
  final SpatialBus bus;
  final String spatialIntent;
  final bool pooled;
  final String? description;
}
```

**Stage Categories:**
| Category | Examples |
|----------|----------|
| `spin` | SPIN_START, SPIN_END, REEL_SPINNING |
| `win` | WIN_PRESENT, WIN_LINE_SHOW, ROLLUP_* |
| `feature` | FEATURE_ENTER, FREESPIN_*, BONUS_* |
| `cascade` | CASCADE_START, CASCADE_STEP, CASCADE_END |
| `jackpot` | JACKPOT_TRIGGER, JACKPOT_AWARD |
| `hold` | HOLD_*, RESPINS_* |
| `gamble` | GAMBLE_ENTER, GAMBLE_EXIT |
| `ui` | UI_*, SYSTEM_* |
| `music` | MUSIC_*, ATTRACT_* |
| `symbol` | SYMBOL_LAND, WILD_*, SCATTER_* |
| `custom` | User-defined stages |

**EventRegistry Integration:**
- Replaced 4 hardcoded functions with service delegation
- `_shouldUsePool()` → `StageConfigurationService.instance.isPooled()`
- `_stageToPriority()` → `StageConfigurationService.instance.getPriority()`
- `_stageToBus()` → `StageConfigurationService.instance.getBus()`
- `_stageToIntent()` → `StageConfigurationService.instance.getSpatialIntent()`

**Initialization:** `main.dart` — `StageConfigurationService.instance.init();`

---

### AudioContextService — Auto-Action System ✅ 2026-01-24

Context-aware auto-action system that automatically determines Play/Stop actions based on audio file name and stage type.

**Service:** `flutter_ui/lib/services/audio_context_service.dart` (~310 LOC)

**Core Enums:**
```dart
enum AudioContext { baseGame, freeSpins, bonus, holdWin, jackpot, unknown }
enum AudioType { music, sfx, voice, ambience, unknown }
enum StageType { entry, exit, step, other }
```

**API:**
```dart
AudioContextService.instance.determineAutoAction(
  audioPath: 'fs_music_theme.wav',
  stage: 'FS_TRIGGER',
);
// Returns: AutoActionResult(actionType: ActionType.play, reason: '...')

// Detection methods
AudioContext detectContextFromAudio(String audioPath);  // fs_*, base_*, bonus_*
AudioType detectAudioType(String audioPath);            // music_*, sfx_*, vo_*
AudioContext detectContextFromStage(String stage);      // FS_*, BONUS_*, HOLD_*
StageType detectStageType(String stage);                // _TRIGGER, _EXIT, _STEP
```

**Auto-Action Logic:**
| Audio Type | Stage Type | Context Match | Result |
|------------|------------|---------------|--------|
| SFX / Voice | Any | - | **PLAY** |
| Music / Ambience | Entry (_TRIGGER, _ENTER) | Same | **PLAY** |
| Music / Ambience | Entry | Different | **STOP** (stop old music) |
| Music / Ambience | Exit (_EXIT, _END) | - | **STOP** |
| Music / Ambience | Step (_STEP, _TICK) | - | **PLAY** |

**Context Detection Patterns:**

| Prefix | Detected Context |
|--------|------------------|
| `fs_`, `freespin`, `free_spin` | FREE_SPINS |
| `bonus`, `_bonus` | BONUS |
| `hold`, `respin`, `holdwin` | HOLD_WIN |
| `jackpot`, `grand`, `major` | JACKPOT |
| `base_`, `main_` | BASE_GAME |

**EventDraft Integration:**
```dart
class EventDraft {
  ActionType actionType;    // Auto-determined
  String? stopTarget;       // Bus to stop (for Stop actions)
  String actionReason;      // Human-readable explanation
}
```

**QuickSheet UI:**
- Green badge + ▶ icon for **PLAY** actions
- Red badge + ⬛ icon for **STOP** actions
- Info tooltip shows `actionReason` explanation
- Displays `stopTarget` when applicable

**Example Scenarios:**
1. Drop `base_music.wav` on `FS_TRIGGER` → **STOP** (stop base music when FS starts)
2. Drop `fs_music.wav` on `FS_TRIGGER` → **PLAY** (play FS music when FS starts)
3. Drop `spin_sfx.wav` on anything → **PLAY** (SFX always plays)
4. Drop `base_music.wav` on `FS_EXIT` → **STOP** (stop music when leaving)

---

### P3.4 — GDD Import Wizard ✅ 2026-01-23 (V9: 2026-01-26)

Multi-step wizard for importing Game Design Documents with auto-stage generation.

**Service:** `flutter_ui/lib/services/gdd_import_service.dart` (~1500 LOC)

**GDD Models:**
```dart
class GameDesignDocument {
  final String name;
  final String version;
  final GddGridConfig grid;
  final List<GddSymbol> symbols;
  final List<GddFeature> features;
  final GddMathModel math;
  final List<String> customStages;

  // V9: Convert to Rust-expected format
  Map<String, dynamic> toRustJson();
}

class GddGridConfig {
  final int rows;
  final int columns;
  final String mechanic; // 'lines', 'ways', 'cluster', 'megaways'
  final int? paylines;
  final int? ways;
}

class GddSymbol {
  final String id;
  final String name;
  final SymbolTier tier; // low, mid, high, premium, wild, scatter, bonus
  final Map<int, double> payouts;
  final bool isWild, isScatter, isBonus;
}
```

**V9: toRustJson() Conversion:**
```dart
Map<String, dynamic> toRustJson() => {
  'game': { 'name': name, 'volatility': volatility, 'target_rtp': rtp },
  'grid': { 'reels': columns, 'rows': rows, 'paylines': paylines },
  'symbols': symbols.map((s) => {
    'id': index, 'name': s.name, 'type': symbolTypeStr(s),
    'pays': payoutsToArray(s.payouts),  // [0,0,20,50,100]
    'tier': tierToNum(s.tier),          // 1-8
  }).toList(),
  'math': { 'symbol_weights': { 'Zeus': [5,5,5,5,5], ... } },
};
```

**V9: Dynamic Slot Symbol Registry:**
```dart
// slot_preview_widget.dart
class SlotSymbol {
  static Map<int, SlotSymbol> _dynamicSymbols = {};
  static void setDynamicSymbols(Map<int, SlotSymbol> symbols);
  static Map<int, SlotSymbol> get effectiveSymbols;
}

// slot_lab_screen.dart — called after GDD import
void _populateSlotSymbolsFromGdd(List<GddSymbol> gddSymbols) {
  // Convert to SlotSymbol with tier colors + theme emojis
  SlotSymbol.setDynamicSymbols(converted);
}
```

**Wizard Widget:** `flutter_ui/lib/widgets/slot_lab/gdd_import_wizard.dart` (~780 LOC)

**Preview Dialog (V8):** `flutter_ui/lib/widgets/slot_lab/gdd_preview_dialog.dart` (~450 LOC)
- Visual slot mockup (columns × rows grid)
- Math panel (RTP, volatility, hit frequency)
- Symbol list with auto-assigned emojis
- Features list with types
- Apply/Cancel confirmation

**4-Step Flow:**
| Step | Name | Actions |
|------|------|---------|
| 1 | **Input** | Paste JSON, Load file, Load PDF text |
| 2 | **Preview** | Review parsed GDD, symbols, features |
| 3 | **Stages** | View auto-generated stages |
| 4 | **Confirm** | Import to StageConfigurationService |

**V9 Complete Integration Flow:**
```
GDD Import → toRustJson() → Rust Engine
           → _populateSlotSymbolsFromGdd() → Reel Display
           → _PaytablePanel(gddSymbols) → Paytable Panel
           → _slotLabSettings.copyWith() → Grid Dimensions
```

**Auto-Stage Generation:**
- Per-reel stops: `REEL_STOP_0..N`
- Per-symbol lands: `SYMBOL_LAND_[SYMBOL_ID]`
- Per-feature stages: `[FEATURE]_ENTER`, `[FEATURE]_EXIT`, `[FEATURE]_STEP`
- Win tier stages: `WIN_[TIER]_START`, `WIN_[TIER]_END`

**V8 Provider Storage:**
```dart
// Store GDD in provider (persists to project file)
SlotLabProjectProvider.importGdd(gdd, generatedSymbols: symbols);

// Access later
final gdd = provider.importedGdd;       // Full GDD
final grid = provider.gridConfig;       // Grid config only
final symbols = provider.gddSymbols;    // GDD symbols
final features = provider.gddFeatures;  // GDD features
```

**Theme-Specific Symbol Detection (90+ symbols):**
- Greek: Zeus, Poseidon, Hades, Athena, Medusa, Pegasus, etc.
- Egyptian: Ra, Anubis, Horus, Cleopatra, Pharaoh, Scarab, etc.
- Asian: Dragon, Tiger, Phoenix, Koi, Panda, etc.
- Norse: Odin, Thor, Freya, Loki, Mjolnir, etc.
- Irish/Celtic: Leprechaun, Shamrock, Pot of Gold, etc.

**V9: Symbol Weight Distribution by Tier:**
| Tier | Weight (per reel) | Rust Type |
|------|-------------------|-----------|
| Wild | 2 | `wild` |
| Scatter | 3 | `scatter` |
| Bonus | 3 | `bonus` |
| Premium | 5 | `high_pay` |
| High | 8 | `high_pay` |
| Mid | 12 | `mid_pay` |
| Low | 18 | `low_pay` |

**Dokumentacija:** `.claude/architecture/GDD_IMPORT_SYSTEM.md`

---

### P3.5 — Container Visualization ✅ 2026-01-23

Interactive visualizations for all container types.

**Widgets:** `flutter_ui/lib/widgets/middleware/container_visualization_widgets.dart` (~970 LOC)

**BlendRtpcSlider:**
- Interactive RTPC slider with real-time volume preview
- Shows active blend region with color gradient
- Volume meters per child responding to RTPC position

**RandomWeightPieChart:**
- Pie chart showing weight distribution
- Color-coded segments per child
- Labels with percentage and name
- CustomPainter implementation

**RandomSelectionHistory:**
- Last N selections visualized as bars
- Shows randomness distribution over time
- Highlights when selection matches weight expectation

**SequenceTimelineVisualization:**
- Horizontal timeline with step blocks
- Play/Stop preview with progress indicator
- Step timing visualization (delay + duration)
- Loop/Hold/PingPong end behavior indicator
- CustomPainter for timeline rendering

**ContainerTypeBadge:**
- Compact badge showing container type
- Color-coded: Blend=purple, Random=amber, Sequence=teal

**ContainerPreviewCard:**
- Summary card for container lists
- Shows type, child count, key parameters

**Integration:**
- `blend_container_panel.dart` — Added BlendRtpcSlider
- `random_container_panel.dart` — Added RandomWeightPieChart
- `sequence_container_panel.dart` — Added SequenceTimelineVisualization with play/stop

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
- `premium_slot_preview.dart` — Fullscreen premium UI (~4,100 LOC)
- `slot_preview_widget.dart` — Reel animation system (~1,500 LOC)
- `stage_trace_widget.dart` — Animated timeline kroz stage evente
- `event_log_panel.dart` — Real-time log audio eventa
- `forced_outcome_panel.dart` — Test buttons (keyboard shortcuts 1-0)
- `audio_hover_preview.dart` — Browser sa hover preview

**Premium Preview Mode (2026-01-24) — 100% Complete, P1+P2+P3 Done:**
```
A. Header Zone — Menu, logo, balance, VIP, audio, settings, exit     ✅ 100%
B. Jackpot Zone — 4-tier tickers + progressive meter                  ✅ 100%
C. Main Game Zone — Reels, paylines, win overlay, anticipation        ✅ 100%
D. Win Presenter — Rollup, gamble, tier badges, coin particles        ✅ 100%
E. Feature Indicators — Free spins, bonus meter, multiplier           ✅ 100%
F. Control Bar — Lines/Coin/Bet selectors, Auto-spin, Turbo, Spin    ✅ 100%
G. Info Panels — Paytable, rules, history, stats (from engine)       ✅ 100%
H. Audio/Visual — Volume slider, music/sfx toggles (persisted)       ✅ 100%
```

**✅ P1 Completed — Critical (Audio Testing):**

| Feature | Solution | Status |
|---------|----------|--------|
| Cascade animation | `_CascadeOverlay` — falling symbols, glow, rotation | ✅ Done |
| Wild expansion | `_WildExpansionOverlay` — expanding star, sparkle particles | ✅ Done |
| Scatter collection | `_ScatterCollectOverlay` — flying diamonds with trails | ✅ Done |
| Audio toggles | Connected to `NativeFFI.setBusMute()` (bus 1=SFX, 2=Music) | ✅ Done |

**✅ P2 Completed — Realism:**

| Feature | Solution | Status |
|---------|----------|--------|
| Collect/Gamble | Full gamble flow with double-or-nothing, card pick | ✅ Done (Gamble disabled 2026-01-24) |
| Paytable | `_PaytablePanel` connected via `slotLabExportPaytable()` FFI | ✅ Done |
| RNG connection | `_getEngineRandomGrid()` via `slotLabSpin()` FFI | ✅ Done |
| Jackpot growth | `_tickJackpots()` uses `_progressiveContribution` from bet math | ✅ Done |

**✅ P3 Completed — Polish:**

| Feature | Solution | Status |
|---------|----------|--------|
| Menu functionality | `_MenuPanel` with Paytable/Rules/History/Stats/Settings/Help | ✅ Done |
| Rules from config | `_GameRulesConfig.fromJson()` via `slotLabExportConfig()` FFI | ✅ Done |
| Settings persistence | SharedPreferences for turbo/music/sfx/volume/quality/animations | ✅ Done |
| Theme consolidation | `_SlotTheme` documented with FluxForgeTheme color mappings | ✅ Done |

**Keyboard Shortcuts:**
| Key | Action |
|-----|--------|
| F11 | Toggle fullscreen preview |
| ESC | Exit / close panels |
| Space | Spin / Stop (if spinning) |
| M | Toggle music |
| S | Toggle stats |
| T | Toggle turbo |
| A | Toggle auto-spin |
| 1-7 | Force outcomes (debug) |

**Forced Outcomes:**
```
1-Lose, 2-SmallWin, 3-BigWin, 4-MegaWin, 5-EpicWin,
6-FreeSpins, 7-JackpotGrand, 8-NearMiss, 9-Cascade, 0-UltraWin
```

**Visual Improvements (2026-01-24):**

| Feature | Implementation | Status |
|---------|---------------|--------|
| **Win Line Painter** | `_WinLinePainter` CustomPainter — connecting lines through winning positions with glow, core, dots | ✅ Done |
| **STOP Button** | Spin button shows "STOP" (red) during spin, SPACE key stops immediately | ✅ Done |
| **Gamble Disabled** | `showGamble: false` + `if (false && _showGambleScreen)` — code preserved for future | ✅ Done |
| **Audio-Visual Sync Fix** | `onReelStop` fires at visual landing (entering `bouncing` phase), not after bounce | ✅ Done |

**Win Line Rendering:**
- Outer glow with MaskFilter blur
- Main colored line (win tier color)
- White highlight core
- Glowing dots at each symbol position
- Pulse animation via `_winPulseAnimation`

**STOP Flow:**
1. SPACE pressed or STOP button clicked during spin
2. `provider.stopStagePlayback()` stops audio stages
3. `_reelAnimController.stopImmediately()` stops visual animation
4. Display grid updated to final target values
5. `_finalizeSpin()` triggers win presentation

**Audio-Visual Sync Fix (P0.1):**
- **Problem:** Audio played 180ms after visual reel landing (triggered when bounce animation completed)
- **Root Cause:** `onReelStop` callback fired when phase became `stopped` (after bounce) instead of `bouncing` (at landing)
- **Fix:** Changed `professional_reel_animation.dart:tick()` to fire `onReelStop` when entering `bouncing` phase
- **Impact:** Audio now plays precisely when reel visually lands
- **Analysis:** `.claude/analysis/AUDIO_VISUAL_SYNC_ANALYSIS_2026_01_24.md`

**IGT-Style Sequential Reel Stop Buffer (2026-01-25) ✅:**
- **Problem:** Animation callbacks fire out-of-order (Reel 4 might complete before Reel 3)
- **Root Cause:** Each reel animation runs independently, completion order is non-deterministic
- **Solution:** Sequential buffer pattern — audio triggers ONLY in order 0→1→2→3→4
- **Implementation:** `_nextExpectedReelIndex` + `_pendingReelStops` buffer in `slot_preview_widget.dart`
- **Flow:** If Reel 4 finishes before Reel 3, it gets buffered. When Reel 3 finishes, both 3 and 4 are flushed in order.

**V8: Enhanced Win Plaque Animation (2026-01-25) ✅:**

| Feature | Description | Status |
|---------|-------------|--------|
| **Screen Flash** | 150ms white/gold flash on plaque entrance | ✅ Done |
| **Plaque Glow Pulse** | 400ms pulsing glow during display | ✅ Done |
| **Particle Burst** | 10-80 particles based on tier (ULTRA=80, EPIC=60, MEGA=45, SUPER=30, BIG=20, SMALL=10) | ✅ Done |
| **Tier Scale Multiplier** | ULTRA=1.25x, EPIC=1.2x, MEGA=1.15x, SUPER=1.1x, BIG=1.05x | ✅ Done |
| **Enhanced Slide** | 80px slide distance for BIG+ tiers | ✅ Done |

**Controllers added:**
- `_screenFlashController` — 150ms flash animation
- `_screenFlashOpacity` — 0.8→0.0 fade
- `_plaqueGlowController` — 400ms repeating pulse
- `_plaqueGlowPulse` — 0.7→1.0 intensity

**STOP Button Control System (2026-01-25) ✅:**
- **Problem:** STOP button showed during win presentation, not just reel spinning
- **Solution:** Separate `isReelsSpinning` from `isPlayingStages`
- **Implementation:**
  - `SlotLabProvider.isReelsSpinning` — true ONLY during reel animation
  - `SlotLabProvider.onAllReelsVisualStop()` — called by slot_preview_widget
  - `_ControlBar.showStopButton` — new parameter for STOP visibility
- **Flow:** SPIN_START → `isReelsSpinning=true` → All reels stop → `isReelsSpinning=false` → Win presentation continues
- **Analysis:** `.claude/analysis/SLOTLAB_EVENT_FLOW_ANALYSIS_2026_01_25.md`

**6-Phase Reel Animation System (Industry Standard):**

| Phase | Duration | Easing | Description |
|-------|----------|--------|-------------|
| IDLE | — | — | Stationary, čeka spin |
| ACCELERATING | 100ms | easeOutQuad | 0 → puna brzina |
| SPINNING | 560ms+ | linear | Konstantna brzina |
| DECELERATING | 300ms | easeInQuad | Usporava |
| BOUNCING | 200ms | elasticOut | 15% overshoot |
| STOPPED | — | — | Mirovanje |

**Per-Reel Stagger (Studio Profile):** 370ms između reelova = 2220ms total

**Animation Specification:** `.claude/architecture/SLOT_ANIMATION_INDUSTRY_STANDARD.md`

**Industry-Standard Win Presentation Flow (2026-01-24) ✅:**

3-fazni win presentation flow prema NetEnt, Pragmatic Play, Big Time Gaming standardima.
**VAŽNO:** BIG WIN je **PRVI major tier** (5x-15x), SUPER je drugi tier (umesto nestandardnog "NICE").

| Phase | Duration | Audio Stages | Visual |
|-------|----------|--------------|--------|
| **Phase 1** | 1050ms (3×350ms) | WIN_SYMBOL_HIGHLIGHT | Winning symbols glow/bounce |
| **Phase 2** | 1500-20000ms (tier-based) | WIN_PRESENT_[TIER], ROLLUP_* | Tier plaque ("BIG WIN!") + coin counter rollup |
| **Phase 3** | 1500ms/line | WIN_LINE_SHOW | Win line cycling (STRICT SEQUENTIAL — after rollup) |

**Win Tier System (Industry Standard):**

| Tier | Multiplier | Plaque Label | Rollup | Ticks/sec |
|------|------------|--------------|--------|-----------|
| SMALL | < 5x | "WIN!" | 1500ms | 15 |
| **BIG** | **5x - 15x** | **"BIG WIN!"** | 2500ms | 12 |
| SUPER | 15x - 30x | "SUPER WIN!" | 4000ms | 10 (ducks) |
| MEGA | 30x - 60x | "MEGA WIN!" | 7000ms | 8 (ducks) |
| EPIC | 60x - 100x | "EPIC WIN!" | 12000ms | 6 (ducks) |
| ULTRA | 100x+ | "ULTRA WIN!" | 20000ms | 4 (ducks) |

**Key Features:**
- ✅ Phase 3 starts **STRICTLY AFTER** Phase 2 ends (no overlap)
- ✅ Tier plaque hides when Phase 3 starts
- ✅ Win lines show **ONLY visual lines** (no symbol info like "3x Grapes")
- ✅ BIG WIN is **FIRST major tier** per Zynga, NetEnt, Pragmatic Play

**Implementation:**
- `slot_preview_widget.dart` — `_rollupDurationByTier`, `_rollupTickRateByTier`, `_getWinTier()`
- `stage_configuration_service.dart` — WIN_PRESENT_[TIER] stage definitions
- Spec: `.claude/analysis/WIN_PRESENTATION_INDUSTRY_STANDARD_2026_01_24.md`

**Dokumentacija:** `.claude/architecture/SLOT_LAB_SYSTEM.md`, `.claude/architecture/PREMIUM_SLOT_PREVIEW.md`

**V9: GDD Import → Complete Slot Machine Integration (2026-01-26) ✅:**

Kada korisnik importuje GDD, SVE informacije se učitavaju u slot mašinu:
- Grid dimenzije (reels × rows)
- Simboli sa emoji-ima i bojama
- Paytable sa payout vrednostima
- Symbol weights za Rust engine
- Volatility i RTP

| Step | Action |
|------|--------|
| 1 | User clicks GDD Import button |
| 2 | GddPreviewDialog shows parsed GDD with grid preview |
| 3 | User clicks "Apply Configuration" |
| 4 | `projectProvider.importGdd(gdd)` — perzistencija |
| 5 | `_populateSlotSymbolsFromGdd()` — dinamički simboli na reelovima |
| 6 | `slotLabProvider.initEngineFromGdd(toRustJson())` — Rust engine |
| 7 | Grid settings applied + `_isPreviewMode = true` |
| 8 | Fullscreen PremiumSlotPreview opens with GDD symbols |

**Implementacija** (`slot_lab_screen.dart:3038-3070`):
```dart
// 1. Store in provider
projectProvider.importGdd(result.gdd, generatedSymbols: result.generatedSymbols);

// 2. Populate dynamic slot symbols for reel display
_populateSlotSymbolsFromGdd(result.gdd.symbols);

// 3. Initialize Rust engine with GDD
final gddJson = jsonEncode(result.gdd.toRustJson());
slotLabProvider.initEngineFromGdd(gddJson);

// 4. Apply grid and open fullscreen
setState(() {
  _slotLabSettings = _slotLabSettings.copyWith(
    reels: newReels,
    rows: newRows,
    volatility: _volatilityFromGdd(result.gdd.math.volatility),
  );
  _isPreviewMode = true;
});
```

**V9 Novi fajlovi/metode:**
| Lokacija | Metoda/Feature |
|----------|----------------|
| `gdd_import_service.dart` | `toRustJson()` — Dart→Rust konverzija |
| `slot_preview_widget.dart` | `SlotSymbol.setDynamicSymbols()` — dinamički registar |
| `slot_lab_screen.dart` | `_populateSlotSymbolsFromGdd()` — konverzija simbola |
| `slot_lab_screen.dart` | `_getSymbolEmojiForReel()` — 70+ emoji mapiranja |
| `slot_lab_screen.dart` | `_getSymbolColorsForTier()` — tier boje |
| `premium_slot_preview.dart` | `_PaytablePanel(gddSymbols)` — paytable iz GDD-a |

**Dokumentacija:** `.claude/architecture/GDD_IMPORT_SYSTEM.md`

### SlotLab V6 Layout (2026-01-23) ✅ COMPLETE

Reorganizovani Lower Zone, novi widgeti i 3-panel layout za V6.

**3-Panel Layout:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ HEADER                                                               │
├────────────┬──────────────────────────────────┬─────────────────────┤
│            │                                  │                     │
│  SYMBOL    │         CENTER                   │    EVENTS           │
│  STRIP     │   (Timeline + Stage Trace +      │    PANEL            │
│  (220px)   │    Slot Preview)                 │    (300px)          │
│            │                                  │                     │
│ - Symbols  │                                  │ - Events Folder     │
│ - Music    │                                  │ - Selected Event    │
│   Layers   │                                  │ - Audio Browser     │
│            │                                  │                     │
├────────────┴──────────────────────────────────┴─────────────────────┤
│ LOWER ZONE (7 tabs + menu)                                          │
└─────────────────────────────────────────────────────────────────────┘
```

**Tab Reorganization (15 → 7 + menu):**

| Tab | Sadrži | Keyboard |
|-----|--------|----------|
| Timeline | Stage trace, waveforms, layers | Ctrl+Shift+T |
| Events | Event list + RTPC (merged) | Ctrl+Shift+E |
| Mixer | Bus hierarchy + Aux sends (merged) | Ctrl+Shift+X |
| Music/ALE | ALE rules, signals, transitions | Ctrl+Shift+A |
| Meters | LUFS, peak, correlation | Ctrl+Shift+M |
| Debug | Event log, trace history | Ctrl+Shift+D |
| Engine | Profiler + resources + stage ingest | Ctrl+Shift+G |
| [+] Menu | Game Config, AutoSpatial, Scenarios, Command Builder | — |

**Novi Widgeti:**

| Widget | Fajl | LOC | Opis |
|--------|------|-----|------|
| `SymbolStripWidget` | `widgets/slot_lab/symbol_strip_widget.dart` | ~400 | Symbols + Music Layers sa drag-drop |
| `EventsPanelWidget` | `widgets/slot_lab/events_panel_widget.dart` | ~580 | Events folder + Audio browser + File/Folder import |
| `CreateEventDialog` | `widgets/slot_lab/create_event_dialog.dart` | ~420 | Event creation popup sa stage selection |

**EventsPanelWidget Features (V6.1):**
- Events folder tree sa create/delete
- Audio browser sa drag-drop
- Pool mode toggle za DAW↔SlotLab sync
- File import (📄) — Multiple audio files via FilePicker
- Folder import (📁) — Rekurzivni scan direktorijuma
- AudioAssetManager integration
- **Audio Hover Preview (V6.2)** — 500ms hover delay, auto-play, waveform visualization

**SymbolStripWidget Features (V6.2):**
- Symbols + Music Layers sa drag-drop
- Per-section audio count badges
- **Reset Buttons** — Per-section reset sa confirmation dialog
- Expandable symbol items sa context audio slots

**Data Models:** `flutter_ui/lib/models/slot_lab_models.dart`
- `SymbolDefinition` — Symbol type, emoji, contexts (land/win/expand)
- `ContextDefinition` — Game chapter (base/freeSpins/holdWin/bonus)
- `SymbolAudioAssignment` — Symbol→Audio mapping
- `MusicLayerAssignment` — Context→Layer→Audio mapping
- `SlotLabProject` — Complete project state for persistence

**Provider:** `flutter_ui/lib/providers/slot_lab_project_provider.dart`
- Symbol CRUD + audio assignments
- Context CRUD + music layer assignments
- Project save/load (JSON)
- GDD import integration
- ALE provider connection for music layer sync
- **Bulk Reset Methods (V6.2):**
  - `resetSymbolAudioForContext(context)` — Reset all symbol audio for context
  - `resetSymbolAudioForSymbol(symbolId)` — Reset all audio for symbol
  - `resetAllSymbolAudio()` — Reset ALL symbol audio assignments
  - `resetMusicLayersForContext(contextId)` — Reset music layers for context
  - `resetAllMusicLayers()` — Reset ALL music layer assignments
  - `getAudioAssignmentCounts()` — Get counts per section for UI badges

**Integration:**
- `slot_lab_screen.dart` — 3-panel layout with Consumer<SlotLabProjectProvider>
- Symbol audio drop → Syncs to EventRegistry for playback
- Music layer drop → Syncs to SlotLabProjectProvider + ALE profile generation

**ALE Sync Methods:**
- `generateAleProfile()` — Export all contexts/layers as ALE-compatible JSON
- `getContextAudioPaths()` — Get audio paths for a context (layer → path map)
- `_syncMusicLayerToAle()` — Real-time sync on layer assignment

**GetIt Registration:** Layer 5.5 — `sl.registerLazySingleton<SlotLabProjectProvider>(() => SlotLabProjectProvider());`

**Implementation Status:** All 9 phases complete (2026-01-23)
- Phase 1-5: Tab reorganization, Symbol Strip, Events Panel, Plus Menu
- Phase 6: Data Models (slot_lab_models.dart)
- Phase 7: Layout Integration (3-panel structure)
- Phase 8: Provider Registration (GetIt Layer 5.5)
- Phase 9: FFI Integration (EventRegistry sync, ALE profile generation)

**Dokumentacija:** `.claude/tasks/SLOTLAB_V6_IMPLEMENTATION.md`

**Enhanced Symbol System:** `.claude/architecture/DYNAMIC_SYMBOL_CONFIGURATION.md` — Data-driven symbol configuration sa presets, Add/Remove UI, i automatskim stage generisanjem

### SlotLab V6.2 — Gap Fixes (2026-01-24) ✅ COMPLETE

Critical gaps identified and fixed in SlotLab screen.

**P1: Export to EventRegistry** ✅
- Location: [slot_lab_screen.dart:7800](flutter_ui/lib/screens/slot_lab_screen.dart#L7800) (export button)
- Helper: `_convertCommittedEventToAudioEvent()` at line 1843
- Converts `CommittedEvent` (draft format) → `AudioEvent` (playable format)
- Bus ID mapping: Master=0, Music=1, SFX=2, Voice=3, UI=4, Ambience=5
- Auto-detects loop mode for Music bus events
- Priority mapping via `_intentToPriority()` (Jackpot=90, BigWin=80, etc.)

**P2.1: Add Symbol Dialog** ✅
- Location: `_showAddSymbolDialog()` at line 4120
- Features: Name field, emoji picker (12 options), symbol type dropdown, audio contexts chips
- Creates `SymbolDefinition` with id, name, emoji, type, contexts
- Quick presets for common symbol types (Wild, Scatter, High, Low, Bonus)

**P2.2: Add Context Dialog** ✅
- Location: `_showAddContextDialog()` at line 4201
- Features: Display name, icon picker (12 emojis), context type dropdown, layer count
- Creates `ContextDefinition` with id, displayName, icon, type, layerCount
- Quick presets: Base Game, Free Spins, Hold & Win, Bonus, Big Win, Cascade, Jackpot, Gamble
- Context type mapping via `_contextTypeName()` helper

**P2.3: Container Editor Navigation** ✅
- Location: line 8870 (container open button)
- Shows SnackBar with "OPEN IN MIDDLEWARE" action button
- Action calls `widget.onClose()` to navigate from SlotLab → Middleware section
- User can then access Blend/Random/Sequence container panels in Middleware

**Usage:**
```dart
// Export events to EventRegistry
final audioEvent = _convertCommittedEventToAudioEvent(committedEvent);
eventRegistry.registerEvent(audioEvent);

// Add symbol via dialog
_showAddSymbolDialog();  // Opens dialog, adds to SlotLabProjectProvider

// Add context via dialog
_showAddContextDialog(); // Opens dialog, adds to SlotLabProjectProvider
```

### SlotLab V6.3 — UX Improvements (2026-01-25) ✅ COMPLETE

Quality-of-life improvements for audio authoring workflow.

**Audio Hover Preview (EventsPanelWidget):**
- 500ms hover delay before playback starts
- Waveform visualization during preview
- Play/Stop toggle button on hover
- Green accent when playing, blue when idle
- Stops on mouse exit

**Reset Buttons (SymbolStripWidget):**
- Audio count badge in section headers (blue badge with count)
- Reset button (🔄) appears when audio is assigned
- Confirmation dialog before destructive action
- Per-section reset (Symbols / Music Layers)

**Implementation Files:**
| File | Changes |
|------|---------|
| `events_panel_widget.dart` | `_AudioBrowserItemWrapper`, `_HoverPreviewItem`, `_SimpleWaveformPainter` |
| `symbol_strip_widget.dart` | Reset callbacks, count badges, confirmation dialog |
| `slot_lab_project_provider.dart` | 6 bulk reset methods |
| `slot_lab_screen.dart` | Reset callback wiring |

### Bonus Game Simulator (P2.20) — IMPLEMENTED ✅ 2026-01-23

Unified bonus feature testing panel sa FFI integracijom.

**Rust Engine:** `crates/rf-slot-lab/src/engine_v2.rs`
- Pick Bonus metode (`is_pick_bonus_active`, `pick_bonus_make_pick`, `pick_bonus_complete`)
- Gamble metode (`is_gamble_active`, `gamble_make_choice`, `gamble_collect`)
- Hold & Win (već implementirano — 12+ metoda)

**FFI Bridge:** `crates/rf-bridge/src/slot_lab_ffi.rs`
- Pick Bonus: 9 funkcija (`slot_lab_pick_bonus_*`)
- Gamble: 7 funkcija (`slot_lab_gamble_*`)
- Hold & Win: 12 funkcija (postojeće)

**Dart FFI:** `flutter_ui/lib/src/rust/native_ffi.dart`
```dart
// Pick Bonus
bool pickBonusIsActive()
Map<String, dynamic>? pickBonusMakePick()
Map<String, dynamic>? pickBonusGetStateJson()
double pickBonusComplete()

// Gamble
bool gambleIsActive()
Map<String, dynamic>? gambleMakeChoice(int choiceIndex)
double gambleCollect()
Map<String, dynamic>? gambleGetStateJson()
```

**UI Widget:** `flutter_ui/lib/widgets/slot_lab/bonus/bonus_simulator_panel.dart` (~780 LOC)
- Tabbed interface: Hold & Win | Pick Bonus | Gamble
- Quick trigger buttons
- Status badges (active/inactive)
- FFI-driven state display
- Last payout tracking

**Bonus Widgets:**
| Widget | Fajl | LOC | Opis |
|--------|------|-----|------|
| `BonusSimulatorPanel` | `bonus_simulator_panel.dart` | ~780 | Unified tabbed panel |
| `HoldAndWinVisualizer` | `hold_and_win_visualizer.dart` | ~688 | Grid + locked symbols |
| `PickBonusPanel` | `pick_bonus_panel.dart` | ~641 | Interactive pick grid |
| `GambleSimulator` | `gamble_simulator.dart` | ~641 | Card/coin gamble UI |

**Feature Coverage:**
| Feature | Backend | FFI | UI | Status |
|---------|---------|-----|----|----|
| Hold & Win | ✅ | ✅ | ✅ | 100% |
| Pick Bonus | ✅ | ✅ | ✅ | 100% |
| Gamble | ✅ | ✅ | ✅ | 100% |
| Wheel Bonus | ❌ | ❌ | ❌ | Optional |

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
- `.claude/domains/slot-audio-events-master.md` — Master katalog 600+ eventa (V1.2)

**State Persistence:**
- Audio pool, composite events, tracks, event→region mapping
- Čuva se u Provider, preživljava switch između sekcija

**Audio Cutoff Prevention (2026-01-24) ✅:**

Problem: `_onMiddlewareChanged()` re-registrovao sve evente, što je prekidalo audio koji je trenutno svirao.

Rešenje: `_eventsAreEquivalent()` funkcija u EventRegistry:
```dart
bool _eventsAreEquivalent(AudioEvent a, AudioEvent b) {
  // Poredi basic fields + sve layere
  // Ako su identični → preskoči re-registraciju
  // Ako su različiti → stopEventSync() pa registruj
}
```

**Auto-Acquire SlotLab Section (2026-01-24) ✅:**

Problem: Bez aktivne sekcije, audio ne bi svirao jer `UnifiedPlaybackController.activeSection` je bio null.

Rešenje: EventRegistry sada automatski acquireuje SlotLab sekciju ako nijedna nije aktivna:
```dart
if (activeSection == null) {
  UnifiedPlaybackController.instance.acquireSection(PlaybackSection.slotLab);
  UnifiedPlaybackController.instance.ensureStreamRunning();
}
```

**Fallback Stage Resolution (2026-01-24) ✅:**

Problem: Jedan generički zvuk (REEL_STOP) ne svira kada se trigeruju specifični stage-ovi (REEL_STOP_0, REEL_STOP_1...).

Rešenje: `_getFallbackStage()` mapira specifične stage-ove na generičke:
```dart
// REEL_STOP_0 → REEL_STOP (ako REEL_STOP_0 nije registrovan)
// CASCADE_STEP_3 → CASCADE_STEP
// SYMBOL_LAND_5 → SYMBOL_LAND
```

**Podržani fallback pattern-i:**
| Specific | Generic |
|----------|---------|
| `REEL_STOP_0..4` | `REEL_STOP` |
| `CASCADE_STEP_N` | `CASCADE_STEP` |
| `WIN_LINE_SHOW_N` | `WIN_LINE_SHOW` |
| `SYMBOL_LAND_N` | `SYMBOL_LAND` |
| `ROLLUP_TICK_N` | `ROLLUP_TICK` |

**Dokumentacija:** `.claude/architecture/EVENT_SYNC_SYSTEM.md`

**Symbol Audio Re-Registration on Mount (2026-01-25) ✅:**

Problem: Symbol audio events (WIN_SYMBOL_HIGHLIGHT_HP1, SYMBOL_LAND_WILD, etc.) registrovani direktno u EventRegistry (ne preko MiddlewareProvider), pa se gube kada se SlotLab screen remountuje.

**Dva odvojena flow-a za audio evente:**
1. **Main flow:** DropTargetWrapper → QuickSheet → MiddlewareProvider (persistirano)
2. **Symbol flow:** SymbolStripWidget → `projectProvider.assignSymbolAudio()` → direktan `eventRegistry.registerEvent()` (NIJE persistirano u EventRegistry)

**Root Cause:**
- `SlotLabProjectProvider.symbolAudio` JE persistirano (List<SymbolAudioAssignment>)
- Ali EventRegistry eventi NISU — gube se pri remount-u
- Rezultat: Symbol audio ne svira nakon navigacije između sekcija

**Rešenje:** Nova metoda `_syncSymbolAudioToRegistry()` u `slot_lab_screen.dart`:
```dart
void _syncSymbolAudioToRegistry() {
  final symbolAudio = projectProvider.symbolAudio;
  for (final assignment in symbolAudio) {
    final stageName = assignment.stageName;  // WIN_SYMBOL_HIGHLIGHT_HP1
    final audioEvent = AudioEvent(
      id: 'symbol_${assignment.symbolId}_${assignment.context}',
      stage: stageName,
      layers: [AudioLayer(audioPath: assignment.audioPath, ...)],
    );
    eventRegistry.registerEvent(audioEvent);
  }
}
```

**Poziv u `_initializeSlotEngine()`** — uvek se izvršava, nezavisno od engine init rezultata.

**Stage Name Generation (`SymbolAudioAssignment.stageName`):**
| Context | Stage Format |
|---------|--------------|
| `win` | `WIN_SYMBOL_HIGHLIGHT_HP1` |
| `land` | `SYMBOL_LAND_HP1` |
| `expand` | `SYMBOL_EXPAND_HP1` |
| `lock` | `SYMBOL_LOCK_HP1` |
| `transform` | `SYMBOL_TRANSFORM_HP1` |

**Ključni fajlovi:**
- `slot_lab_screen.dart:10404-10459` — `_syncSymbolAudioToRegistry()` metoda
- `slot_lab_screen.dart:1547-1553` — Poziv u `_initializeSlotEngine()`
- `slot_lab_models.dart:654-669` — `SymbolAudioAssignment.stageName` getter

### StageGroupService & generateEventName() (2026-01-24) ✅

Konverzija stage imena u human-readable event imena + batch import matching.

**Lokacija:** `flutter_ui/lib/services/stage_group_service.dart`

**Intent-Based Matching v2.0:**

Umesto simple keyword matching-a, koristi se INTENT pattern recognition:

| Intent | Indicators | Excludes | Example Match |
|--------|------------|----------|---------------|
| **SPIN_START** | spin + (button/click/press/ui/start) | loop, roll, spinning | `spin_button.wav` |
| **REEL_SPIN** | spin + (loop/roll/reel/spinning) | button, press, click, stop | `reel_spin_loop.wav` |
| **REEL_STOP** | stop/land + reel context | spinning, loop | `reel_stop.wav` |

**Smart Exclusion Logic:**
- If 3+ keyword matches → excludes are overridden (strong intent)
- If 1-2 matches and 2+ excludes → excluded
- If more excludes than matches → excluded

**generateEventName() Mapping:**
| Stage | Event Name |
|-------|------------|
| `SPIN_START` | `onUiSpin` |
| `REEL_STOP_0` | `onReelLand1` |
| `REEL_STOP_1` | `onReelLand2` |
| `REEL_STOP_2` | `onReelLand3` |
| `REEL_STOP_3` | `onReelLand4` |
| `REEL_STOP_4` | `onReelLand5` |
| `WIN_BIG` | `onWinBig` |
| `CASCADE_STEP` | `onCascadeStep` |
| `FREESPIN_START` | `onFreeSpinStart` |

**Note:** REEL_STOP je 0-indexed u stage-ovima, ali 1-indexed u event imenima (intuitivnije za dizajnere).

**Batch Import Matching (2026-01-24):**

Podržava OBA formata imenovanja fajlova:
- **0-indexed:** `stop_0.wav`, `stop_1.wav`, ... → REEL_STOP_0, REEL_STOP_1, ...
- **1-indexed:** `stop_1.wav`, `stop_2.wav`, ... → REEL_STOP_0, REEL_STOP_1, ...

| File Name | Matches Stage | Notes |
|-----------|---------------|-------|
| `reel_stop_0.wav` | REEL_STOP_0 | 0-indexed |
| `stop_1.wav` | REEL_STOP_0 | 1-indexed first reel |
| `land_2.wav` | REEL_STOP_1 | 1-indexed second reel |
| `reel_land_5.wav` | REEL_STOP_4 | 1-indexed fifth reel |
| `spin_stop.wav` | REEL_STOP | Generic (no specific reel) |

**Batch Import Test:**
```dart
final result = StageGroupService.instance.matchFilesToGroup(
  group: StageGroup.spinsAndReels,
  audioPaths: ['/audio/stop_1.wav', '/audio/stop_2.wav', '/audio/stop_3.wav'],
);
// stop_1.wav → REEL_STOP_0 (onReelLand1)
// stop_2.wav → REEL_STOP_1 (onReelLand2)
// stop_3.wav → REEL_STOP_2 (onReelLand3)
```

**Debug Utility:**
```dart
// Dijagnoza zašto audio fajl ne matčuje stage
StageGroupService.instance.debugTestMatch('reel_stop_1.wav');
// Output: MATCHED: REEL_STOP_1 (85%), Event name: onReelLand2

// Run all matching tests:
StageGroupService.instance.runMatchingTests();
// Output: 24 passed, 0 failed
```

**Batch Import Auto-Expand (2026-01-24):**

Kada se importuje JEDAN generički audio fajl (npr. `reel_stop.wav`), sistem automatski kreira 5 per-reel eventa sa stereo panning-om.

**Implementacija:** `slot_lab_screen.dart:_expandGenericStage()`

```
DROP: reel_stop.wav (matches REEL_STOP)
         ↓
AUTO-EXPAND to 5 events:
  ├── REEL_STOP_0 → onReelLand1 (pan: -0.8)
  ├── REEL_STOP_1 → onReelLand2 (pan: -0.4)
  ├── REEL_STOP_2 → onReelLand3 (pan: 0.0)
  ├── REEL_STOP_3 → onReelLand4 (pan: +0.4)
  └── REEL_STOP_4 → onReelLand5 (pan: +0.8)
```

**Expandable Stages:**

| Stage Pattern | Expands To | Pan | Notes |
|---------------|------------|-----|-------|
| `REEL_STOP` | `REEL_STOP_0..4` | ✅ | Stereo spread L→R |
| `REEL_LAND` | `REEL_LAND_0..4` | ✅ | Alias for REEL_STOP |
| `WIN_LINE_SHOW` | `WIN_LINE_SHOW_0..4` | ✅ | Per-reel win highlights |
| `WIN_LINE_HIDE` | `WIN_LINE_HIDE_0..4` | ✅ | Per-reel win hide |
| `CASCADE_STEP` | `CASCADE_STEP_0..4` | ❌ | Center (no pan) |
| `SYMBOL_LAND` | `SYMBOL_LAND_0..4` | ❌ | Center (no pan) |

**Stage Fallback (2026-01-24):**

Ako korisnik ima samo JEDAN generički event (`REEL_STOP`), a sistem trigeruje specifični stage (`REEL_STOP_0`), automatski koristi fallback:

```
triggerStage('REEL_STOP_0')
    ↓
Look for REEL_STOP_0 → NOT FOUND
    ↓
Fallback: REEL_STOP → FOUND!
    ↓
Play REEL_STOP event
```

**Fallbackable Patterns:** `REEL_STOP`, `CASCADE_STEP`, `WIN_LINE_SHOW/HIDE`, `SYMBOL_LAND`, `ROLLUP_TICK`, `WHEEL_TICK`

**Dokumentacija:** `.claude/architecture/EVENT_SYNC_SYSTEM.md`, `.claude/domains/slot-audio-events-master.md`

### Event Naming Service (2026-01-24) ✅

Singleton servis za generisanje semantičkih imena eventa iz targetId i stage.

**Lokacija:** `flutter_ui/lib/services/event_naming_service.dart` (~650 LOC)

**API:**
```dart
EventNamingService.instance.generateEventName(targetId, stage);
// 'ui.spin', 'SPIN_START' → 'onUiPaSpinButton'
// 'reel.0', 'REEL_STOP_0' → 'onReelStop0'
// null, 'FS_TRIGGER' → 'onFsTrigger'
```

**Naming Patterns:**

| Stage Category | Pattern | Example |
|----------------|---------|---------|
| UI Elements | `onUiPa{Element}` | `onUiPaSpinButton` |
| Reel Events | `onReel{Action}{Index}` | `onReelStop0` |
| Free Spins | `onFs{Phase}` | `onFsTrigger`, `onFsEnter` |
| Bonus | `onBonus{Phase}` | `onBonusTrigger`, `onBonusEnter` |
| Win Events | `onWin{Tier}` | `onWinSmall`, `onWinBig` |
| Jackpot | `onJackpot{Tier}` | `onJackpotMini`, `onJackpotGrand` |
| Cascade | `onCascade{Phase}` | `onCascadeStart`, `onCascadeStep` |
| Hold & Win | `onHold{Phase}` | `onHoldTrigger`, `onHoldSpin` |
| Gamble | `onGamble{Phase}` | `onGambleStart`, `onGambleWin` |
| Tumble | `onTumble{Phase}` | `onTumbleDrop`, `onTumbleLand` |
| Menu | `onMenu{Action}` | `onMenuOpen`, `onMenuClose` |
| Autoplay | `onAutoplay{Action}` | `onAutoplayStart`, `onAutoplayStop` |

**Stage Coverage:** 100+ stage pattern-a pokriveno iz StageConfigurationService

**Integration:**
- `AutoEventBuilderProvider.createDraft()` koristi ovaj servis za generisanje eventId
- QuickSheet automatski prikazuje semantičko ime
- Events Panel prikazuje 3-kolonski format: NAME | STAGE | LAYERS

**Event Name Editing (2026-01-24):**

| Lokacija | Trigger | Behavior |
|----------|---------|----------|
| QuickSheet | Direktno | TextField, edit pre commit-a |
| Events Panel | Double-tap | Inline edit mode, orange border |

**QuickSheet:** Ime je editable TextField umesto readonly text. Korisnik može promeniti pre commit-a.

**Events Panel:** Double-tap na event ulazi u inline edit mode:
- Orange border indikator
- Edit ikona zamenjuje audiotrack
- Enter ili focus loss → auto-save
- Koristi `MiddlewareProvider.updateCompositeEvent()`

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

### SlotLab Drop Zone System (2026-01-23) ✅

Drag-drop audio na mockup elemente → automatsko kreiranje eventa.

**Arhitektura:**
```
Audio File (Browser) → Drop on Mockup Element → CommittedEvent
                                                     ↓
                                          SlotCompositeEvent
                                                     ↓
                                          MiddlewareProvider (SSoT)
                                                     ↓
                    ┌────────────────────────────────┼────────────────────────────────┐
                    ▼                                ▼                                ▼
              Timeline Track                  EventRegistry                   Events Folder
              + Region + Layers              (stage trigger)                  (Middleware)
```

**Key Features:**
- 35+ drop targets (ui.spin, reel.0-4, overlay.win.*, symbol.*, music.*, etc.)
- Per-reel auto-pan: `(reelIndex - 2) * 0.4` (reel.0=-0.8, reel.2=0.0, reel.4=+0.8)
- Automatic stage mapping (targetId → SPIN_START, REEL_STOP_0, WIN_BIG, etc.)
- Bus routing (SFX, Reels, Wins, Music, UI, etc.)
- Visual feedback (glow, pulse, event count badge)

**Bridge Implementation:** `slot_lab_screen.dart:_onEventBuilderEventCreated()`

**Edit Mode UI (V6.1):**
- Enhanced mode toggle button sa glow efektom (active) i clear labels
- "DROP ZONE ACTIVE" banner iznad slot grida kada je edit mode aktivan
- EXIT button za brzi izlaz iz edit mode-a
- Visual hierarchy: Banner → Slot Grid → Controls

**Dokumentacija:** `.claude/architecture/SLOTLAB_DROP_ZONE_SPEC.md`

### Dynamic Symbol Configuration (2026-01-25) 📋 SPEC READY

Data-driven sistem za konfiguraciju simbola u SlotLab mockup-u.

**Problem:** Hardkodirani simboli (HP1, HP2, MP1, LP1...) ne odgovaraju svim igrama.

**Rešenje:** Dinamička konfiguracija simbola koju dizajner može prilagoditi:
- Add/Remove simbole po potrebi
- Presets za različite tipove igara (Standard 5x3, Megaways, Hold & Win)
- Automatsko generisanje stage-ova po simbolu

**Ključni modeli:**
```dart
enum SymbolType { wild, scatter, bonus, highPay, mediumPay, lowPay, custom }
enum SymbolAudioContext { land, win, expand, lock, transform, collect }

class SymbolDefinition {
  final String id;           // 'hp1', 'wild', 'mystery'
  final String name;         // 'High Pay 1', 'Wild'
  final String emoji;        // '🃏', '⭐', '❓'
  final SymbolType type;
  final Set<SymbolAudioContext> audioContexts;

  String get stageIdLand => 'SYMBOL_LAND_${id.toUpperCase()}';
  String get stageIdWin => 'WIN_SYMBOL_HIGHLIGHT_${id.toUpperCase()}';
}
```

**Implementation Phases (7):** ~1,450 LOC total

**Dokumentacija:** `.claude/architecture/DYNAMIC_SYMBOL_CONFIGURATION.md`

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
| P0.8 | RTL (Right-to-Left) Rollup Animation | ✅ Done |
| P0.9 | Win Tier 1 Rollup Skip | ✅ Done |
| P0.10 | Symbol Drop Zone Rules | ✅ Done |
| P0.11 | Larger Drop Targets | ✅ Done |
| P1.1 | Symbol-Specific Audio | ✅ Done |
| P1.2 | Near Miss Audio Escalation | ✅ Done |
| P1.3 | Win Line Audio Panning | ✅ Done |

**Ključni fajlovi:**
- `crates/rf-engine/src/playback.rs` — Per-voice pan, seamless looping
- `crates/rf-slot-lab/src/timing.rs` — TimingConfig sa latency compensation
- `flutter_ui/lib/services/rtpc_modulation_service.dart` — Rollup/Cascade speed RTPC
- `flutter_ui/lib/services/event_registry.dart` — Big Win templates, context pan/volume
- `flutter_ui/lib/providers/slot_lab_provider.dart` — Pre-trigger, timing config, symbol detection

**Dokumentacija:** `.claude/architecture/SLOT_LAB_AUDIO_FEATURES.md` (kompletni tehnički detalji — P0.1-P0.11, P1.1-P1.3)

### SlotLab 100% Industry Standard Audio (2026-01-25) ✅

Kompletiranje industry-standard audio sistema za slot igre.

**Novi feature-i implementirani:**

| ID | Feature | Status | Opis |
|----|---------|--------|------|
| P0 | Per-Reel Spin Loop Fade-out | ✅ Done | Svaki reel ima svoj spin loop voice, fade-out 50ms na REEL_STOP_X |
| P1.1 | WIN_EVAL Audio Gap Bridge | ✅ Done | Stage između poslednjeg REEL_STOP i WIN_PRESENT za bridging |
| P1.2 | Rollup Volume Dynamics | ✅ Done | Volume escalation 0.85x → 1.15x tokom rollup-a |
| P2 | Anticipation Pre-Trigger | ✅ Done | Audio pre-trigger za anticipation stage-ove |

**P0: Per-Reel Spin Loop Tracking**

Svaki reel ima nezavisni REEL_SPIN_LOOP voice koji se fade-out-uje individualno.

```dart
// event_registry.dart
final Map<int, int> _reelSpinLoopVoices = {};  // reelIndex → voiceId

void _trackReelSpinLoopVoice(int reelIndex, int voiceId) {
  _reelSpinLoopVoices[reelIndex] = voiceId;
}

void _fadeOutReelSpinLoop(int reelIndex) {
  final voiceId = _reelSpinLoopVoices.remove(reelIndex);
  if (voiceId != null) {
    AudioPlaybackService.instance.fadeOutVoice(voiceId, fadeMs: 50);
  }
}
```

**Auto-detekcija stage-ova:**
- `REEL_SPINNING_0..4` → Pokreće spin loop za specifični reel
- `REEL_STOP_0..4` → Fade-out spin loop za specifični reel
- `SPIN_END` → Fallback: zaustavlja sve preostale spin loop-ove

**P1.1: WIN_EVAL Stage**

Bridging stage između poslednjeg REEL_STOP i WIN_PRESENT:
- Trigeruje se nakon REEL_STOP_4
- Omogućava audio design za "evaluaciju" winova
- Sprečava audio prazninu između faza

**P1.2: Rollup Volume Dynamics**

Volume escalation tokom rollup-a za dramatični efekat:

```dart
// rtpc_modulation_service.dart
double getRollupVolumeEscalation(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return 0.85 + (p * 0.30);  // 0.85x → 1.15x
}
```

**FFI Chain za Fade-out:**
```
Dart: AudioPlaybackService.fadeOutVoice(voiceId, fadeMs: 50)
  → NativeFFI.playbackFadeOutOneShot(voiceId, fadeMs)
    → C FFI: engine_playback_fade_out_one_shot(voice_id, fade_ms)
      → Rust: PlaybackEngine.fade_out_one_shot(voice_id, fade_ms)
```

**Ključni fajlovi:**
- `flutter_ui/lib/services/event_registry.dart` — Per-reel tracking, stage auto-detection
- `flutter_ui/lib/services/audio_playback_service.dart` — fadeOutVoice() metoda
- `flutter_ui/lib/src/rust/native_ffi.dart` — FFI binding za fade-out
- `crates/rf-engine/src/ffi.rs:19444` — C FFI export
- `crates/rf-engine/src/playback.rs:2608` — Rust fade_out_one_shot()

**Dokumentacija:** `.claude/analysis/SLOTLAB_100_INDUSTRY_STANDARD_2026_01_25.md`

### SlotLab Industry Standard Fixes (2026-01-25) ✅

P0 Critical fixes za profesionalni slot audio — eliminacija audio-visual desync problema.

**P0 Tasks Completed:**

| ID | Feature | Status | Opis |
|----|---------|--------|------|
| P0.1 | Per-Reel Spin Loop + Fade-Out | ✅ Done | Svaki reel ima nezavisni spin loop sa 50ms fade-out |
| P0.2 | Dead Silence Pre Win Reveal | ✅ Done | Pre-trigger WIN_SYMBOL_HIGHLIGHT na poslednjem reel stop-u |
| P0.3 | Anticipation Visual-Audio Sync | ✅ Done | Callbacks za sinhronizaciju visual efekata sa audio-m |

**P0.1: Per-Reel Spin Loop with Independent Fade-Out**

Rust Stage variants za per-reel audio kontrolu:

```rust
// crates/rf-stage/src/lib.rs
pub enum Stage {
    // Per-reel spin lifecycle stages
    ReelSpinningStart { reel_index: u8 },  // Start spin loop for specific reel
    ReelSpinningStop { reel_index: u8 },   // Stop spin loop for specific reel
    // ... existing variants
}
```

**Auto-detection u event_registry.dart:**
- `REEL_SPINNING_START_0..4` → Pokreće spin loop za specifični reel
- `REEL_STOP_0..4` → Fade-out spin loop sa 50ms crossfade
- `SPIN_END` → Fallback: zaustavlja sve preostale spin loop-ove

**P0.2: Pre-Trigger WIN_SYMBOL_HIGHLIGHT**

Eliminacija 50-100ms audio gap-a između poslednjeg reel stop-a i win reveal-a:

```dart
// slot_preview_widget.dart - _triggerReelStopAudio()
if (reelIndex == widget.reels - 1 && !_symbolHighlightPreTriggered) {
  final result = widget.provider.lastResult;
  if (result != null && result.isWin) {
    // Pre-trigger symbol highlights IMMEDIATELY on last reel stop
    for (final symbolName in _winningSymbolNames) {
      eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT_$symbolName');
    }
    eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
    _symbolHighlightPreTriggered = true;  // Prevent double-trigger in _finalizeSpin
  }
}
```

**Flow:** `REEL_STOP_4` → `WIN_SYMBOL_HIGHLIGHT` (instant, no gap)

**P0.3: Anticipation Visual-Audio Sync**

Provider callbacks za sinhronizaciju vizuelnih efekata sa audio-m:

```dart
// slot_lab_provider.dart
void Function(int reelIndex, String reason)? onAnticipationStart;
void Function(int reelIndex)? onAnticipationEnd;

// Callback invocation on ANTICIPATION_ON stage
if (stageType.startsWith('ANTICIPATION_ON')) {
  final reelIdx = _extractReelIndexFromStage(stageType);
  final reason = stage.payload['reason'] as String? ?? 'scatter';
  onAnticipationStart?.call(reelIdx, reason);  // Visual + audio together
}
```

**Speed Multiplier System:**

```dart
// professional_reel_animation.dart
class ReelAnimationState {
  double speedMultiplier = 1.0;  // 1.0 = normal, 0.3 = slow

  void setSpeedMultiplier(double multiplier) {
    speedMultiplier = multiplier.clamp(0.1, 2.0);
  }
}

// Applied in update():
scrollOffset += velocity * 0.1 * speedMultiplier;
```

**Controller API:**

```dart
// ProfessionalReelAnimationController
void setReelSpeedMultiplier(int reelIndex, double multiplier);
void clearAllSpeedMultipliers();  // Called on spin start
```

**Ključni fajlovi:**
- `crates/rf-stage/src/lib.rs` — ReelSpinningStart/Stop stage variants
- `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` — P0.2 pre-trigger, P0.3 callbacks
- `flutter_ui/lib/providers/slot_lab_provider.dart` — P0.3 anticipation callbacks
- `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` — P0.3 speed multiplier

**Dokumentacija:** `.claude/tasks/INDUSTRY_STANDARD_FIXES_PLAN.md`

### Advanced Audio Features (2026-01-25) ✅

**P0.20: Per-Reel Spin Loop System**

Fina kontrola per-reel spin loop-ova sa individualnim fade-out-om:

| Stage Pattern | Svrha |
|---------------|-------|
| `REEL_SPINNING_START_0..4` | Pokreni spin loop za specifični reel |
| `REEL_SPINNING_STOP_0..4` | Early fade-out PRE vizualnog zaustavljanja |
| `REEL_SPINNING_0..4` | Legacy per-reel spin (backwards compat) |

**Implementacija:** `event_registry.dart` — `_reelSpinLoopVoices` map, `_fadeOutReelSpinLoop()`

**P0.21: CASCADE_STEP Pitch/Volume Escalation**

Auto-escalation za cascade korake:

| Step | Stage | Pitch | Volume |
|------|-------|-------|--------|
| 0 | CASCADE_STEP_0 | 1.00x | 90% |
| 1 | CASCADE_STEP_1 | 1.05x | 94% |
| 2 | CASCADE_STEP_2 | 1.10x | 98% |
| 3 | CASCADE_STEP_3 | 1.15x | 102% |
| 4+ | CASCADE_STEP_4+ | 1.20x+ | 106%+ |

**Formula:**
- Pitch: `1.0 + (stepIndex * 0.05)`
- Volume: `0.9 + (stepIndex * 0.04)` (clamped at 1.2)

**P1.5: Jackpot Audio Sequence**

Proširena 6-fazna jackpot sekvenca:

| # | Stage | Duration | Opis |
|---|-------|----------|------|
| 1 | JACKPOT_TRIGGER | 500ms | Alert tone |
| 2 | JACKPOT_BUILDUP | 2000ms | Rising tension |
| 3 | JACKPOT_REVEAL | 1000ms | Tier reveal (MINI/MINOR/MAJOR/GRAND) |
| 4 | JACKPOT_PRESENT | 5000ms | Main fanfare + amount |
| 5 | JACKPOT_CELEBRATION | Loop | Looping celebration |
| 6 | JACKPOT_END | 500ms | Fade out |

**Implementacija:** `crates/rf-slot-lab/src/features/jackpot.rs` — `generate_stages()`

**Dokumentacija:**
- `.claude/architecture/SLOT_LAB_AUDIO_FEATURES.md` — P0.20, P0.21, P1.5 detalji
- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Per-reel spin loop sistem
- `.claude/domains/slot-audio-events-master.md` — V1.2 sa ~110 novih eventa

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
| **SignalCatalogPanel** | `signal_catalog_panel.dart` | ~950 | Katalog 18+ signala, kategorije, normalization curves, test kontrole |
| **RuleTestingSandbox** | `rule_testing_sandbox.dart` | ~1050 | Interaktivni sandbox za testiranje pravila, signal simulacija |
| **StabilityVisualizationPanel** | `stability_visualization_panel.dart` | ~850 | Vizualizacija 7 stability mehanizama |
| **ContextTransitionTimeline** | `context_transition_timeline.dart` | ~900 | Timeline context tranzicija, crossfade preview, beat sync |

**Slot Lab Integration:**
- `SlotLabProvider.connectAle()` — Povezuje ALE provider
- `_syncAleSignals()` — Automatski sync spin rezultata na ALE signale
- `_syncAleContext()` — Automatsko prebacivanje konteksta (BASE/FREESPINS/BIGWIN)
- ALE tab u middleware lower zone (uz Events Folder i Event Editor)

**Dokumentacija:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md` (~2350 LOC)

### AutoSpatial UI Panel (IMPLEMENTED) ✅ 2026-01-22

UI-driven spatial audio positioning system sa kompletnim konfiguracijom panelom.

**Filozofija:** UI Position + Intent + Motion → Intelligent Panning

**Implementacija:**

| Komponenta | Lokacija | LOC | Status |
|------------|----------|-----|--------|
| **Engine** | `flutter_ui/lib/spatial/auto_spatial.dart` | ~2296 | ✅ Done |
| **Provider** | `flutter_ui/lib/providers/auto_spatial_provider.dart` | ~350 | ✅ Done |
| **UI Widgets** | `flutter_ui/lib/widgets/spatial/` | ~3360 | ✅ Done |

**Core Concepts:**

| Koncept | Opis |
|---------|------|
| **IntentRule** | 30+ pravila za mapiranje intenta na spatial ponašanje |
| **BusPolicy** | Per-bus spatial modifikatori (UI, reels, sfx, vo, music, ambience) |
| **AnchorRegistry** | UI element position tracking u normalized screen space |
| **FusionEngine** | Confidence-weighted kombinacija anchor/motion/intent signala |
| **Kalman Filter** | Predictive smoothing za glatke tranzicije |

**UI Panel Tabs:**

| Tab | Widget | Opis |
|-----|--------|------|
| **Intent Rules** | `intent_rule_editor.dart` | CRUD za 30+ intent pravila, JSON export |
| **Bus Policies** | `bus_policy_editor.dart` | 6 buseva, slider kontrole, visual preview |
| **Anchors** | `anchor_monitor.dart` | Real-time anchor vizualizacija, test anchors |
| **Stats & Config** | `spatial_stats_panel.dart` | Engine stats, toggles, listener position |
| **Visualizer** | `spatial_event_visualizer.dart` | 2D radar, color-coded events, test buttons |

**Shared Widgets:** `spatial_widgets.dart`
- SpatialSlider, SpatialDropdown, SpatialToggle
- SpatialMeter, SpatialPanMeter
- SpatialSectionHeader, SpatialBadge

**SlotLab Integration:**
- Tab "AutoSpatial" u lower zone
- Povezan sa EventRegistry preko `_stageToIntent()` (300+ mapiranja)

**Dokumentacija:** `.claude/architecture/AUTO_SPATIAL_SYSTEM.md`

### P3 Advanced Features (2026-01-22) ✅

Kompletni set naprednih feature-a implementiranih u P3 fazi.

#### P3.10: RTPC Macro System

Grupiranje više RTPC bindinga pod jednom kontrolom za dizajnere.

**Models:** `middleware_models.dart`
```dart
class RtpcMacro {
  final int id;
  final String name;
  final double min, max, currentValue;
  final List<RtpcMacroBinding> bindings;

  Map<RtpcTargetParameter, double> evaluate(); // All bindings at once
}

class RtpcMacroBinding {
  final RtpcTargetParameter target;
  final RtpcCurve curve;
  final bool inverted;

  double evaluate(double normalizedMacroValue);
}
```

**Provider API:** `rtpc_system_provider.dart`
- `createMacro({name, min, max, bindings})`
- `setMacroValue(macroId, value, {interpolationMs})`
- `addMacroBinding(macroId, binding)`
- `macrosToJson()` / `macrosFromJson()`

#### P3.11: Preset Morphing

Glatka interpolacija između audio presets sa per-parameter curves.

**Models:** `middleware_models.dart`
```dart
enum MorphCurve {
  linear, easeIn, easeOut, easeInOut,
  exponential, logarithmic, sCurve, step;

  double apply(double t); // 0.0-1.0 → curved value
}

class MorphParameter {
  final RtpcTargetParameter target;
  final double startValue, endValue;
  final MorphCurve curve;

  double valueAt(double t); // Interpolated value
}

class PresetMorph {
  final String presetA, presetB;
  final List<MorphParameter> parameters;
  final double position; // 0.0=A, 1.0=B

  // Factory constructors for common patterns:
  factory PresetMorph.volumeCrossfade(...);
  factory PresetMorph.filterSweep(...);
  factory PresetMorph.tensionBuilder(...);
}
```

**Provider API:** `rtpc_system_provider.dart`
- `createMorph({name, presetA, presetB, parameters})`
- `setMorphPosition(morphId, position)`
- `addMorphParameter(morphId, parameter)`
- `morphsToJson()` / `morphsFromJson()`

#### P3.12: DSP Profiler Panel

Real-time DSP load monitoring sa stage breakdown.

**Models:** `advanced_middleware_models.dart`
```dart
enum DspStage { input, mixing, effects, metering, output, total }

class DspTimingSample {
  final Map<DspStage, double> stageTimingsUs;
  final int blockSize;
  final double sampleRate;

  double get loadPercent; // 0-100%
  bool get isOverloaded; // > 90%
}

class DspProfiler {
  void record({stageTimingsUs, blockSize, sampleRate});
  DspProfilerStats getStats();
  List<double> getLoadHistory({count: 100});
  void simulateSample({baseLoad: 15.0}); // For testing
}
```

**Widget:** `flutter_ui/lib/widgets/middleware/dsp_profiler_panel.dart`
- Big load display (percentage)
- Horizontal bar meter with warning/critical thresholds
- Load history graph (time series)
- Stage breakdown (IN/MIX/FX/MTR/OUT)
- Statistics (avg, min, max, overloads)
- Reset/Pause controls

#### P3.13: Live WebSocket Parameter Channel

Throttled real-time parameter updates over WebSocket do game engines.

**Models:** `websocket_client.dart`
```dart
enum ParameterUpdateType {
  rtpc, volume, pan, mute, solo,
  morphPosition, macroValue, containerState,
  stateGroup, switchGroup
}

class ParameterUpdate {
  final ParameterUpdateType type;
  final String targetId;
  final double? numericValue;
  final String? stringValue;
  final bool? boolValue;

  factory ParameterUpdate.rtpc(rtpcId, value);
  factory ParameterUpdate.morphPosition(morphId, position);
  factory ParameterUpdate.macroValue(macroId, value);
  // ... more factories
}
```

**Service:** `LiveParameterChannel`
- Throttling: ~30Hz max (33ms interval)
- Per-parameter throttle timers
- Methods: `sendRtpc()`, `sendMorphPosition()`, `sendMacroValue()`, `sendVolume()`, etc.

#### P3.14: Visual Routing Matrix UI

Track→Bus routing matrix sa click-to-route i send level controls.

**Widget:** `flutter_ui/lib/widgets/routing/routing_matrix_panel.dart`

**Features:**
- Grid layout: tracks (rows) × buses (columns)
- Click cell to toggle route (on/off)
- Long-press on aux bus cell for send level dialog
- Visual indicators for active routes
- Send level display (dB)
- Pre/Post fader toggle for aux sends

**Models:**
```dart
class RoutingNode {
  final int id;
  final String name;
  final RoutingNodeType type; // track, bus, aux, master
  final double volume, pan;
  final bool muted, soloed;
}

class RoutingConnection {
  final int sourceId, targetId;
  final double sendLevel;
  final bool preFader, enabled;
}
```

---

### Priority Features (2026-01-23) ✅

Five priority features from Ultimate System Analysis — all implemented.

**Documentation:** `.claude/architecture/PRIORITY_FEATURES_2026_01_23.md`

| # | Feature | Role | Location | LOC |
|---|---------|------|----------|-----|
| 1 | Visual Reel Strip Editor | Slot Game Designer | `widgets/slot_lab/reel_strip_editor.dart` | ~800 |
| 2 | In-Context Auditioning | Audio Designer | `widgets/slot_lab/in_context_audition.dart` | ~500 |
| 3 | Visual State Machine Graph | Middleware Architect | `widgets/middleware/state_machine_graph.dart` | ~600 |
| 4 | DSP Profiler Rust FFI | Engine Developer | `profiler_ffi.rs` + `native_ffi.dart` | ~400 |
| 5 | Command Palette | Tooling Developer | `widgets/common/command_palette.dart` | ~750 |

**Total:** ~3,050 LOC

**Key Features:**

1. **Reel Strip Editor:**
   - Drag-drop symbol reordering
   - Symbol palette (14 types)
   - Statistics panel (distribution, frequency)
   - Import/export JSON

2. **In-Context Auditioning:**
   - Timeline presets (spin, win, big win, free spins, cascade, bonus)
   - A/B comparison mode
   - Playhead scrubbing
   - Quick audition buttons

3. **State Machine Graph:**
   - Node-based visual editor
   - Transition arrows with animation
   - Current state highlighting
   - Zoom/pan canvas

4. **DSP Profiler FFI:**
   - Real Rust engine metrics
   - Per-stage breakdown (input, mixing, effects, metering, output)
   - Fallback simulation mode
   - Rust: `profiler_get_current_load()`, `profiler_get_stage_breakdown_json()`

5. **Command Palette:**
   - VS Code-style Ctrl+Shift+P
   - Fuzzy search with scoring
   - Recent items tracking
   - Pre-built FluxForge commands

**Usage:**

```dart
// Reel Strip Editor
ReelStripEditor(initialStrips: strips, onStripsChanged: callback)

// In-Context Audition
InContextAuditionPanel(eventRegistry: registry)
QuickAuditionButton(context: AuditionContext.bigWin, eventRegistry: registry)

// State Machine Graph
StateMachineGraph(stateGroup: group, currentStateId: id, onStateSelected: callback)

// Command Palette
CommandPalette.show(context, commands: FluxForgeCommands.getDefaultCommands(...))
```

**Bug Fixes (2026-01-23):**
- `Duration.clamp()` → manual clamping (Duration nema clamp metodu)
- `PopupMenuDivider<void>()` → `PopupMenuDivider()` (nema type parameter)
- `iconColor` → `Icon(color: ...)` (parameter ne postoji na IconButton)
- `StateGroup.currentState` → `StateGroup.currentStateId` (ispravan API)
- `_dylib` → `_loadNativeLibrary().lookupFunction<>()` (FFI pattern)
- `EventRegistry` dependency → callback-based `onTriggerStage`

**Verification:** `flutter analyze` — No errors (11 info-level only)

---

### M3.1 Sprint — Middleware Improvements (2026-01-23) ✅

P1 priority tasks from middleware analysis completed.

**TODO 1: RTPC Debugger Panel** ✅
- Location: [rtpc_debugger_panel.dart](flutter_ui/lib/widgets/middleware/rtpc_debugger_panel.dart) (~1159 LOC)
- Real-time value meters with sparkline history
- Slider controls for live parameter adjustment
- Binding visualization with output preview
- Search, recording toggle, reset controls
- Exported via middleware_exports.dart

**TODO 2: Tab Categories in Lower Zone** ✅
- Location: [lower_zone_controller.dart](flutter_ui/lib/controllers/slot_lab/lower_zone_controller.dart) (+100 LOC)
- `LowerZoneCategory` enum: audio, routing, debug, advanced
- `LowerZoneCategoryConfig` with label, icon, description
- Category field added to `LowerZoneTabConfig`
- Collapse state (advanced collapsed by default)
- Helper functions: `getTabsInCategory()`, `getTabsByCategory()`, `getCategoryForTab()`
- Actions: `toggleCategory()`, `setCategoryCollapsed()`, `expandAllCategories()`
- Serialization includes category collapse state

**TODO 3: Trace Export CSV** ✅
- Location: [event_profiler_provider.dart](flutter_ui/lib/providers/subsystems/event_profiler_provider.dart) (+85 LOC)
- `exportToCSV()` method with proper escaping
- Format: `timestamp,eventId,type,description,soundId,busId,voiceId,latencyUs`
- `exportToCSVCustom()` for custom column selection
- `getCSVExportInfo()` for row count and file size estimation

**Verification:** `flutter analyze` — No errors (11 info-level only)

**Documentation:** `.claude/architecture/MIDDLEWARE_TODO_M3_2026_01_23.md`

---

### M3.2 Sprint — Middleware Improvements (2026-01-23) ✅

P2 priority tasks from middleware analysis completed.

**TODO 4: Waveform Trim Editor** ✅
- Location: [waveform_trim_editor.dart](flutter_ui/lib/widgets/common/waveform_trim_editor.dart) (~380 LOC)
- Draggable trim handles (start/end)
- Fade in/out curve handles with visual feedback
- Right-click context menu (Reset Trim, Zoom Selection, Normalize)
- Non-destructive trim stored as `trimStartMs`, `trimEndMs` on SlotEventLayer
- Model updates: [slot_audio_events.dart](flutter_ui/lib/models/slot_audio_events.dart)

**TODO 5: Ducking Preview Mode** ✅
- Service: [ducking_preview_service.dart](flutter_ui/lib/services/ducking_preview_service.dart) (~230 LOC)
- Panel update: [ducking_matrix_panel.dart](flutter_ui/lib/widgets/middleware/ducking_matrix_panel.dart) (+150 LOC)
- Preview button appears when rule is selected
- Visual ducking curve with CustomPainter (`_DuckingCurvePainter`)
- Real-time envelope visualization (ideal vs actual curve)
- Phase indicators: Attack (orange), Sustain (cyan), Release (purple)
- Progress bar and current duck level percentage

**TODO 6: Workspace Presets** ✅
- Model: [workspace_preset.dart](flutter_ui/lib/models/workspace_preset.dart) (~210 LOC)
- Service: [workspace_preset_service.dart](flutter_ui/lib/services/workspace_preset_service.dart) (~280 LOC)
- Dropdown: [workspace_preset_dropdown.dart](flutter_ui/lib/widgets/lower_zone/workspace_preset_dropdown.dart) (~340 LOC)
- 5 built-in presets: Audio Design, Routing, Debug, Mixing, Spatial
- Custom preset CRUD (create, update, delete, duplicate)
- SharedPreferences persistence with JSON serialization
- Export/Import JSON support for preset sharing
- Integrated into `LowerZoneContextBar` via `presetDropdown` parameter

**WorkspacePresetService** (Singleton):
```dart
// Initialize at startup (main.dart)
await WorkspacePresetService.instance.init();

// Get presets for section
final presets = WorkspacePresetService.instance.getPresetsForSection(WorkspaceSection.slotLab);

// Apply preset
await WorkspacePresetService.instance.applyPreset(preset);

// Create custom preset
await WorkspacePresetService.instance.createPreset(
  name: 'My Layout',
  section: WorkspaceSection.slotLab,
  activeTabs: ['events', 'blend'],
  lowerZoneHeight: 350,
);
```

**Verification:** `flutter analyze` — No errors (11 info-level only)

**Documentation:** `.claude/architecture/MIDDLEWARE_TODO_M3_2026_01_23.md`

---

### M4 Sprint — Advanced Features (2026-01-23) ✅

P3 priority tasks completed — all 10 TODO items from middleware analysis done.

**TODO 7: Spectrum Analyzer** ✅ (Already Existed)
- Location: [spectrum_analyzer.dart](flutter_ui/lib/widgets/spectrum/spectrum_analyzer.dart) (~1334 LOC)
- Full-featured FFT display with multiple modes (bars, line, fill, waterfall, spectrogram)
- Peak hold with decay, collision detection, zoom/pan, freeze frame
- Multiple FFT sizes (1024-32768), color schemes
- Integrated in BusHierarchyPanel

**TODO 8: Determinism Mode** ✅
- Model: [middleware_models.dart](flutter_ui/lib/models/middleware_models.dart) — `RandomContainer.seed`, `useDeterministicMode`
- Provider: [random_containers_provider.dart](flutter_ui/lib/providers/subsystems/random_containers_provider.dart) (~120 LOC new)
- Seeded Random instance per container for reproducible results
- `DeterministicSelectionRecord` for QA tracing/replay
- Global deterministic mode toggle
- Selection history export to JSON

```dart
// Enable deterministic mode for a container
provider.setDeterministicMode(containerId, true, seed: 12345);

// Enable global deterministic mode (all containers)
provider.setGlobalDeterministicMode(true);

// Get selection history for replay
final history = provider.getSelectionHistory(containerId);

// Export history for QA
final json = provider.exportSelectionHistoryToJson();
```

**TODO 9: Math Model Connector** ✅
- Model: [win_tier_config.dart](flutter_ui/lib/models/win_tier_config.dart) (~280 LOC)
- Service: [math_model_connector.dart](flutter_ui/lib/services/math_model_connector.dart) (~200 LOC)
- `WinTier` enum (noWin, smallWin, mediumWin, bigWin, megaWin, epicWin, ultraWin, jackpots)
- `WinTierThreshold` with RTPC value, trigger stage, rollup multiplier
- `WinTierConfig` per game with tier thresholds
- Auto-generate RTPC thresholds from paytable
- `AttenuationCurveLink` for dynamic curve linking
- Default configs: Standard, High Volatility, Jackpot

```dart
// Register config
MathModelConnector.instance.registerConfig(DefaultWinTierConfigs.standard);

// Process win and get audio parameters
final result = MathModelConnector.instance.processWin('standard', winAmount, betAmount);
// result.tier, result.rtpcValue, result.triggerStage, result.rollupDuration

// Import from paytable JSON
MathModelConnector.instance.importPaytable(paytableJson);
```

**TODO 10: Interactive Tutorials** ✅
- Step Model: [tutorial_step.dart](flutter_ui/lib/widgets/tutorial/tutorial_step.dart) (~230 LOC)
- Overlay: [tutorial_overlay.dart](flutter_ui/lib/widgets/tutorial/tutorial_overlay.dart) (~320 LOC)
- Content: [first_event_tutorial.dart](flutter_ui/lib/data/tutorials/first_event_tutorial.dart) (~200 LOC)
- `TutorialStep` with spotlight, tooltip position, actions
- `TutorialOverlay` with dark overlay and spotlight cutout
- `TutorialLauncher` widget for Help menu integration
- Built-in tutorials: "Creating Your First Event", "Setting Up RTPC"
- Categories: Basics, Events, Containers, RTPC, Mixing, Advanced
- Difficulty levels: Beginner, Intermediate, Advanced

```dart
// Show tutorial overlay
final completed = await TutorialOverlay.show(
  context,
  tutorial: FirstEventTutorial.tutorial,
);

// Get all tutorials
final tutorials = BuiltInTutorials.all;
```

**Verification:** `flutter analyze` — No errors (11 info-level only)

**Documentation:** `.claude/architecture/MIDDLEWARE_TODO_M3_2026_01_23.md`

**M3-M4 Summary:**
| Sprint | Tasks | LOC | Status |
|--------|-------|-----|--------|
| M3.1 | 3 (P1) | ~1,344 | ✅ DONE |
| M3.2 | 3 (P2) | ~1,590 | ✅ DONE |
| M4 | 4 (P3) | ~2,484 | ✅ DONE |
| **Total** | **10** | **~5,418** | **✅ ALL DONE** |

---

### Universal Stage Ingest System (IMPLEMENTED) ✅ 2026-01-22

Slot-agnostički sistem za integraciju sa bilo kojim game engine-om — **KOMPLETNO IMPLEMENTIRAN**.

**Filozofija:** FluxForge ne razume tuđe evente — razume samo **STAGES** (semantičke faze toka igre).

```
Engine JSON/Events → Adapter → STAGES → FluxForge Audio
```

**Implementacija:**

| Komponenta | Lokacija | LOC | Status |
|------------|----------|-----|--------|
| **rf-stage crate** | `crates/rf-stage/` | ~1200 | ✅ Done |
| **rf-ingest crate** | `crates/rf-ingest/` | ~1800 | ✅ Done |
| **rf-connector crate** | `crates/rf-connector/` | ~950 | ✅ Done |
| **FFI Bridge** | `crates/rf-bridge/src/*_ffi.rs` | ~2400 | ✅ Done |
| **Dart Provider** | `flutter_ui/lib/providers/stage_ingest_provider.dart` | ~1000 | ✅ Done |
| **UI Widgets** | `flutter_ui/lib/widgets/stage_ingest/` | ~2200 | ✅ Done |

**Kanonske STAGES (60+ definisanih):**
```
// Spin Flow
SPIN_START, SPIN_END, REEL_SPINNING, REEL_STOP, REEL_STOP_0..4

// Win Flow
WIN_PRESENT, WIN_LINE_SHOW, WIN_LINE_HIDE, ROLLUP_START, ROLLUP_TICK, ROLLUP_END
BIGWIN_START, BIGWIN_END, MEGAWIN_START, MEGAWIN_END, EPICWIN_START, EPICWIN_END

// Features
ANTICIPATION_ON, ANTICIPATION_OFF, SCATTER_LAND, WILD_LAND
FEATURE_ENTER, FEATURE_STEP, FEATURE_EXIT, FREESPIN_START, FREESPIN_END
BONUS_ENTER, BONUS_EXIT, CASCADE_START, CASCADE_STEP, CASCADE_END

// Special
JACKPOT_TRIGGER, JACKPOT_AWARD, GAMBLE_ENTER, GAMBLE_EXIT
RESPINS_START, RESPINS_END, MULTIPLIER_INCREASE
```

**Tri sloja ingesta:**

| Layer | Rust Trait | Use Case | Opis |
|-------|------------|----------|------|
| **Layer 1: DirectEvent** | `DirectEventAdapter` | Engine sa event log-om | Direktno mapiranje event imena |
| **Layer 2: SnapshotDiff** | `SnapshotDiffAdapter` | Samo pre/posle stanje | Derivacija stage-ova iz diff-a |
| **Layer 3: RuleBased** | `RuleBasedAdapter` | Generički podaci | Heuristička rekonstrukcija |

**Dva režima rada:**

| Mode | Komponente | Flow |
|------|------------|------|
| **OFFLINE** | StageTrace, AdapterWizard, JsonPathExplorer | JSON import → Wizard analysis → Config → Trace → Audio dizajn |
| **LIVE** | Connector (WebSocket/TCP), LiveConnectorPanel | Real-time connection → Stage streaming → Live audio preview |

**Rust Crates:**

**rf-stage** (`crates/rf-stage/`):
- `Stage` enum sa 60+ kanonskih stage tipova
- `StageEvent` — timestamp, stage, metadata
- `StageTrace` — niz eventa sa timing info
- `TimingResolver` — normalizacija i sync timing-a

**rf-ingest** (`crates/rf-ingest/`):
- `Adapter` trait — zajednički interface za sve adaptere
- `AdapterRegistry` — dinamička registracija adaptera
- `IngestConfig` — JSON path mapping, timing config
- `AdapterWizard` — auto-detection i config generacija
- 3 layer implementacije (DirectEvent, SnapshotDiff, RuleBased)

**rf-connector** (`crates/rf-connector/`):
- `Connector` — WebSocket/TCP connection management
- `ConnectorConfig` — host, port, protocol, reconnect
- Event polling sa buffered queue
- Auto-reconnect sa exponential backoff

**FFI Bridge:**
- `stage_ffi.rs` — Stage enum, StageEvent, StageTrace FFI (~800 LOC)
- `ingest_ffi.rs` — Adapter, Config, Wizard FFI (~850 LOC)
- `connector_ffi.rs` — Connector lifecycle, event polling FFI (~750 LOC)

**Flutter Provider** (`stage_ingest_provider.dart`):
```dart
class StageIngestProvider extends ChangeNotifier {
  // Adapter Management
  List<AdapterInfo> get adapters;
  void registerAdapter(String adapterId, String name, IngestLayer layer);

  // Trace Management
  List<StageTraceHandle> get traces;
  StageTraceHandle? createTrace(String traceId, String gameId);
  StageTraceHandle? loadTraceFromJson(String json);
  List<StageEvent> getTraceEvents(int handle);

  // Ingest Config
  IngestConfig? createConfig(String adapterId, String configJson);
  StageTraceHandle? ingestWithConfig(int configId, String json);
  StageTraceHandle? ingestJsonAuto(String json);

  // Wizard
  int? createWizard();
  bool addSampleToWizard(int wizardId, Map<String, dynamic> sample);
  WizardResult? analyzeWizard(int wizardId);

  // Live Connector
  ConnectorHandle? createConnector(String host, int port, ConnectorProtocol protocol);
  void connectConnector(int handle);
  List<StageEvent> pollConnectorEvents(int handle);
}
```

**UI Widgets** (`flutter_ui/lib/widgets/stage_ingest/`):

| Widget | Fajl | LOC | Opis |
|--------|------|-----|------|
| **StageIngestPanel** | `stage_ingest_panel.dart` | ~565 | Glavni panel sa 3 taba (Traces, Wizard, Live) |
| **StageTraceViewer** | `stage_trace_viewer.dart` | ~340 | Timeline vizualizacija sa zoom/scroll, playhead |
| **AdapterWizardPanel** | `adapter_wizard_panel.dart` | ~475 | JSON sample input, analysis, config generation |
| **LiveConnectorPanel** | `live_connector_panel.dart` | ~400 | WebSocket/TCP connection form, real-time event log |
| **EventMappingEditor** | `event_mapping_editor.dart` | ~400 | Visual engine→stage mapping tool |
| **JsonPathExplorer** | `json_path_explorer.dart` | ~535 | JSON structure tree view sa path selection |

**Wizard Auto-Detection:**
```
1. Paste JSON sample(s) iz game engine-a
2. Wizard analizira strukturu i detektuje:
   - Event name polja (type, event, action...)
   - Timestamp polja (timestamp, time, ts...)
   - Reel data (reels, symbols, stops...)
   - Win amount, balance, feature flags
3. Generiše IngestConfig sa confidence score-om
4. Config se koristi za buduće ingest operacije
```

**Live Connection Flow:**
```
1. Unesi host:port i protokol (WebSocket/TCP)
2. Connect → Rust connector uspostavlja konekciju
3. Poll events → Real-time StageEvent-i stižu
4. Events se prosleđuju EventRegistry-ju za audio playback
5. Disconnect/Reconnect sa exponential backoff
```

**SlotLab Integration (2026-01-22):**

| Komponenta | Lokacija | Opis |
|------------|----------|------|
| Provider | `main.dart:194` | `StageIngestProvider` u MultiProvider |
| Lower Zone Tab | `slot_lab_screen.dart` | `stageIngest` tab u `_BottomPanelTab` enum |
| Content Builder | `_buildStageIngestContent()` | Consumer<StageIngestProvider> → StageIngestPanel |
| Audio Trigger | `onLiveEvent` callback | `eventRegistry.triggerStage(event.stage)` |

**Name Collision Resolution:**
- `StageEvent` u `stage_models.dart` (legacy Dart models)
- `IngestStageEvent` u `stage_ingest_provider.dart` (new FFI-based)
- Ultimativno rešenje: renamed class umesto import alias

**Dokumentacija:**
- `.claude/architecture/STAGE_INGEST_SYSTEM.md`
- `.claude/architecture/ENGINE_INTEGRATION_SYSTEM.md`
- `.claude/architecture/SLOT_LAB_SYSTEM.md`
- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — **KRITIČNO: Unified playback across DAW/Middleware/SlotLab**
- `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md` — **Universal Layer Engine: context-aware, metric-reactive music system**

---

## 🔧 TROUBLESHOOTING — SLOTLAB AUDIO NE RADI

### Problem: Spin ne proizvodi zvuk

**Simptomi:**
- Stage-vi se prikazuju u Event Log
- Ali nema audio output-a
- Event Log pokazuje `⚠️ STAGE_NAME (no audio)`

**Root Causes i Rešenja:**

#### 1. EventRegistry je prazan

**Provera:** Event Log status bar pokazuje "No events registered"

**Uzrok:** `_syncAllEventsToRegistry()` nije pozvan pri mount-u SlotLab screen-a

**Fix (2026-01-21):** Dodato u `slot_lab_screen.dart` initState:
```dart
if (_compositeEvents.isNotEmpty) {
  _syncAllEventsToRegistry();
}
```

**Verifikacija:** Debug log treba da pokaže:
```
[SlotLab] Initial sync: X events → EventRegistry
[SlotLab] ✅ Registered "Event Name" under N stage(s)
```

#### 2. Case-sensitivity mismatch

**Uzrok:** SlotLabProvider šalje `"SPIN_START"`, EventRegistry traži `"spin_start"`

**Fix (2026-01-21):** `event_registry.dart` triggerStage() sada radi case-insensitive lookup:
```dart
final normalizedStage = stage.toUpperCase().trim();
// Tries: exact match → normalized → case-insensitive search
```

#### 3. FFI nije učitan

**Simptom:** Event Log pokazuje `FAILED: FFI not loaded`

**Rešenje:** Full rebuild po CLAUDE.md proceduri:
```bash
cargo build --release
cp target/release/*.dylib flutter_ui/macos/Frameworks/
# + xcodebuild + copy to App Bundle
```

#### 4. Nema kreiranih eventa

**Simptom:** Event Log pokazuje `⚠️ SPIN_START (no audio)` za SVE stage-ove

**Rešenje:** Kreiraj AudioEvent-e u SlotLab UI:
1. Events Folder → Create Event
2. Dodeli stage (npr. `SPIN_START`)
3. Dodaj audio layer sa `.wav` fajlom
4. Save

#### 5. Double pozivi u QuickSheet flow-u (2026-01-23)

**Simptom:**
- Drop audio na slot element radi (QuickSheet se prikazuje)
- Commit klik radi (popup se zatvara)
- Ali event se NE kreira u Events panelu
- Spin ne proizvodi zvuk

**Uzrok #1:** `commitDraft()` se pozivao DVAPUT:
1. Prvo u `quick_sheet.dart` onCommit handler
2. Zatim u `drop_target_wrapper.dart` callback

**Uzrok #2:** `createDraft()` se TAKOĐE pozivao DVAPUT:
1. Prvo u `drop_target_wrapper.dart` _handleDrop()
2. Zatim u `quick_sheet.dart` showQuickSheet()

**Fix #1:** Uklonjen `commitDraft()` iz `quick_sheet.dart`
**Fix #2:** Uklonjen `createDraft()` iz `drop_target_wrapper.dart`

**Pravilan flow:**
```
showQuickSheet()           → createDraft() ← JEDINI POZIV
DropTargetWrapper.onCommit → commitDraft() ← JEDINI POZIV
```

**Verifikacija:**
1. Drop audio na SPIN dugme u Edit mode
2. Klikni Commit u QuickSheet popup
3. Event mora da se pojavi u Events panelu (desno)
4. Klikni Spin → audio mora da svira
5. Ponovi za druge elemente (reels, win overlays, itd.)

**Ključni fajlovi:**
- `flutter_ui/lib/widgets/slot_lab/auto_event_builder/quick_sheet.dart` — createDraft()
- `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` — commitDraft()

**Detaljna dokumentacija:** `.claude/architecture/EVENT_SYNC_SYSTEM.md`

### Event Log Format (2026-01-21)

**Sa audio-om:**
```
12:34:56.789  🎵 Spin Sound → SPIN_START [spin.wav, whoosh.wav]
              voice=5, bus=2, section=slotLab
```

**Bez audio-a (upozorava da nedostaje event):**
```
12:34:56.789  ⚠️ REEL_STOP_3 (no audio)
              Create event for this stage to hear audio
```

### Debug Log Patterns

| Log Pattern | Značenje |
|-------------|----------|
| `[SlotLab] Initial sync: X events` | EventRegistry uspešno popunjen |
| `[SlotLab] ✅ Registered "..."` | Event registrovan za stage |
| `[EventRegistry] ❌ No event for stage` | Stage nema registrovan event |
| `[EventRegistry] ✅ Playing: ...` | Audio uspešno pokrenut |
| `FAILED: FFI not loaded` | Dylib-ovi nisu kopirani |

### Relevantna dokumentacija

- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Detalji sync sistema
- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — Playback sekcije
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab arhitektura

#### 6. Double-Spin Trigger (2026-01-24)

**Simptom:**
- Klik na Spin dugme trigeruje DVA spina uzastopno
- Debug log pokazuje dva `[SlotPreview] 🆕 New spin detected`
- Slot mašina odmah pokreće drugi spin nakon prvog

**Uzrok:**
U `_onProviderUpdate()`, nakon što `_finalizeSpin()` postavi `_isSpinning = false`:
- Provider's `isPlayingStages` je još uvek `true` (procesira WIN_PRESENT, ROLLUP, itd.)
- `stages` lista još sadrži 'spin_start'
- Uslov prolazi ponovo → `_startSpin()` se poziva dvaput!

**Fix (2026-01-24):** Dodati guard flagovi u `slot_preview_widget.dart`:

```dart
bool _spinFinalized = false;      // Sprečava re-trigger nakon finalize
String? _lastProcessedSpinId;     // Prati koji spin rezultat je već procesiran

void _onProviderUpdate() {
  // Guards:
  // 1. Ne pokreći ako je spin već finalizovan
  // 2. Ne pokreći ako je isti spinId kao prethodni
  if (isPlaying && stages.isNotEmpty && !_isSpinning && !_spinFinalized) {
    final spinId = result?.spinId;
    if (hasSpinStart && spinId != null && spinId != _lastProcessedSpinId) {
      _lastProcessedSpinId = spinId;
      _startSpin(result);
    }
  }

  // Reset finalized flag kad provider završi (spreman za sledeći spin)
  if (!isPlaying && _spinFinalized) {
    _spinFinalized = false;
  }
}

void _finalizeSpin(SlotLabSpinResult result) {
  setState(() {
    _isSpinning = false;
    _spinFinalized = true;  // KRITIČNO: Sprečava re-trigger
  });
}
```

**Verifikacija:**
1. Klikni Spin → samo jedan spin se pokreće
2. Sačekaj da se završi → samo jedan `✅ FINALIZE SPIN` u logu
3. Klikni ponovo → novi spin se pokreće normalno

**Ključni fajl:** `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

#### 7. SPACE Key Stop-Not-Working (2026-01-26)

**Simptom:**
- SPACE dugme za STOP ne radi u embedded modu (centralni panel)
- Reelovi nastavljaju da se vrte ILI odmah startuju novi spin
- Izgleda kao da SPACE uopšte ne reaguje

**Uzrok:**
Dva nezavisna keyboard handlera procesirala isti SPACE event:
1. Global handler (`slot_lab_screen.dart:_globalKeyHandler`) — preko `HardwareKeyboard.instance.addHandler()`
2. Focus handler (`premium_slot_preview.dart:_handleKeyEvent`) — preko `Focus(onKeyEvent: ...)`

Oba su imala nezavisne debounce timer-e. Kada je SPACE pritisnut za STOP:
- Global handler pozove `stopStagePlayback()` → `isReelsSpinning = false`
- Focus handler vidi `isReelsSpinning = false` → odmah pozove `spin()`
- Rezultat: STOP pa instant SPIN — izgleda kao da SPACE ne radi

**Fix (2026-01-26):** Dodat `isFullscreen` parametar u `PremiumSlotPreview`:

```dart
// premium_slot_preview.dart constructor
const PremiumSlotPreview({
  required this.onExit,
  this.reels = 5,
  this.rows = 3,
  this.isFullscreen = false,  // NEW
});

// In _handleKeyEvent:
case LogicalKeyboardKey.space:
  if (!widget.isFullscreen) {
    return KeyEventResult.ignored;  // Let global handler handle it
  }
  // ... rest of SPACE handling
```

**Instantiation:**
```dart
// Fullscreen mode (F11)
PremiumSlotPreview(isFullscreen: true, ...)

// Embedded mode (centralni panel)
PremiumSlotPreview(isFullscreen: false, ...)
```

**Verifikacija:**
Debug log bi trebao pokazati:
```
# Embedded mode (isFullscreen=false):
[SlotLab] 🌍 GLOBAL Space key handler...
[PremiumSlotPreview] ⏭️ SPACE ignored (embedded mode)

# Fullscreen mode (isFullscreen=true):
[SlotLab] 🌍 GLOBAL Space — SKIPPED (Fullscreen)
[PremiumSlotPreview] 🎰 SPACE pressed...
```

**Ključni fajlovi:**
- `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart:4861,5712`
- `flutter_ui/lib/screens/slot_lab_screen.dart:923,2237,7052`

---

## 🎰 SLOTLAB STAGE FLOW (2026-01-24) ✅

### Kompletan Stage Flow

Redosled stage-ova generisan u `crates/rf-slot-lab/src/spin.rs`:

```
SPIN_START
    ↓
REEL_SPINNING × N (za svaki reel)
    ↓
[ANTICIPATION_ON] (opciono, na poslednja 1-2 reel-a)
    ↓
REEL_STOP_0 → REEL_STOP_1 → ... → REEL_STOP_N
    ↓
[ANTICIPATION_OFF] (ako je bio uključen)
    ↓
EVALUATE_WINS
    ↓
[WIN_PRESENT] (ako ima win)
    ↓
[WIN_LINE_SHOW × N] (za svaku win liniju, max 3)
    ↓
[BIG_WIN_TIER] (ako win_ratio >= threshold)
    ↓
[ROLLUP_START → ROLLUP_TICK × N → ROLLUP_END]
    ↓
[CASCADE_STAGES] (ako ima cascade)
    ↓
[FEATURE_STAGES] (ako je trigerovan feature)
    ↓
SPIN_END
```

### Visual-Sync Mode

**Problem:** Rust timing i Flutter animacija nisu sinhronizovani.

**Rešenje:** `_useVisualSyncForReelStop = true`

Kada je uključen Visual-Sync mode:
- REEL_STOP stage-ovi se **NE triggeruju** iz provider timing-a
- Umesto toga, triggeruju se iz **animacionog callback-a**
- Svaki reel ima svoj callback kada završi animaciju

```dart
// U slot_lab_provider.dart, linija 911-914:
if (_useVisualSyncForReelStop && stage.stageType == 'reel_stop') {
  debugPrint('[SlotLabProvider] 🔇 Skipping REEL_STOP (visual-sync mode)');
  return;  // Audio se triggeruje iz animacije, ne iz providera
}
```

**Callback iz animacije:**
```dart
// professional_reel_animation.dart
onReelStopped: (reelIndex) {
  widget.provider.onReelVisualStop(reelIndex);
}
```

### Reel Faze (ReelPhase enum)

| Faza | Trajanje | Opis |
|------|----------|------|
| `idle` | — | Mirovanje, čeka spin |
| `accelerating` | ~200ms | Ubrzavanje na punu brzinu |
| `spinning` | varijabilno | Puna brzina rotacije |
| `decelerating` | ~300ms | Usporavanje pre zaustavljanja |
| `bouncing` | ~150ms | Bounce efekat na zaustavljanje |
| `stopped` | — | Reel stao, čeka sledeći spin |

### Win Tier Thresholds (Industry Standard — 2026-01-24)

**VAŽNO:** BIG WIN je **PRVI major tier** po industry standardu (Zynga, NetEnt, Pragmatic Play).

| Tier | Win Ratio | Stage | Plaque Label |
|------|-----------|-------|--------------|
| SMALL | < 5x | WIN_PRESENT_SMALL | "WIN!" |
| **BIG** | **5x - 15x** | WIN_PRESENT_BIG | **"BIG WIN!"** |
| SUPER | 15x - 30x | WIN_PRESENT_SUPER | "SUPER WIN!" |
| MEGA | 30x - 60x | WIN_PRESENT_MEGA | "MEGA WIN!" |
| EPIC | 60x - 100x | WIN_PRESENT_EPIC | "EPIC WIN!" |
| ULTRA | 100x+ | WIN_PRESENT_ULTRA | "ULTRA WIN!" |

**Industry Sources:** Wizard of Oz Slots (Zynga), Know Your Slots, NetEnt, Pragmatic Play

### Big Win Celebration System (2026-01-25) ✅

Dedicirani audio sistem za Big Win celebracije (≥20x bet).

**Komponente:**
| Stage | Bus | Priority | Loop | Opis |
|-------|-----|----------|------|------|
| `BIG_WIN_LOOP` | Music (1) | 90 | ✅ Da | Looping celebration muzika, ducks base music |
| `BIG_WIN_COINS` | SFX (2) | 75 | Ne | Coin particle zvuk efekti |

**Trigger Logic (`slot_preview_widget.dart`):**
```dart
final bet = widget.provider.betAmount;
final winRatio = bet > 0 ? result.totalWin / bet : 0.0;
if (winRatio >= 20) {
  eventRegistry.triggerStage('BIG_WIN_LOOP');
  eventRegistry.triggerStage('BIG_WIN_COINS');
}
```

**Auto-Stop (`slot_lab_provider.dart`):**
```dart
void setWinPresentationActive(bool active) {
  if (!active) {
    eventRegistry.stopEvent('BIG_WIN_LOOP');  // Stop loop when win ends
  }
}
```

**UltimateAudioPanel V8 (2026-01-25) ✅ CURRENT:**

Game Flow-based slot audio panel sa **341 audio slotova** organizovanih u **12 sekcija** po toku igre.

| # | Sekcija | Tier | Slots | Boja |
|---|---------|------|-------|------|
| 1 | Base Game Loop | Primary | 41 | #4A9EFF |
| 2 | Symbols & Lands | Primary | 46 | #9370DB |
| 3 | Win Presentation | Primary | 41 | #FFD700 |
| 4 | Cascading Mechanics | Secondary | 24 | #FF6B6B |
| 5 | Multipliers | Secondary | 18 | #FF9040 |
| 6 | Free Spins | Feature | 24 | #40FF90 |
| 7 | Bonus Games | Feature | 32 | #9370DB |
| 8 | Hold & Win | Feature | 24 | #40C8FF |
| 9 | Jackpots | Premium 🏆 | 26 | #FFD700 |
| 10 | Gamble | Optional | 16 | #FF6B6B |
| 11 | Music & Ambience | Background | 27 | #40C8FF |
| 12 | UI & System | Utility | 22 | #808080 |

**V8 Ključne promene:**
- **Game Flow organizacija** — Sekcije prate tok igre (Spin→Stop→Win→Feature)
- **Pooled eventi označeni** — ⚡ ikona za rapid-fire (ROLLUP_TICK, CASCADE_STEP, REEL_STOP)
- **Jackpot izdvojen** — 🏆 Premium sekcija sa validation badge
- **Cascade/Tumble/Avalanche ujedinjeni** — Jedna sekcija za sve cascade mehanike
- **Tier vizualna hijerarhija** — Primary/Secondary/Feature/Premium/Background/Utility

**Persistence:** All expanded states and audio assignments saved via `SlotLabProjectProvider`

**Dokumentacija:** `.claude/architecture/ULTIMATE_AUDIO_PANEL_V8_SPEC.md`

### Anticipation Logic

Anticipation se aktivira kada:
1. Scatter/Bonus simboli se pojave na prva 2-3 reel-a
2. Potencijalni big win je moguć
3. Near-miss situacija

```rust
// U spin.rs
if let Some(ref antic) = self.anticipation {
    if antic.reels.contains(&reel) {
        events.push(StageEvent::new(
            Stage::AnticipationOn { reel_index: reel, reason: Some(antic.reason.clone()) },
            antic_time,
        ));
    }
}
```

### Timing Konfiguracija

Definisano u `crates/rf-slot-lab/src/timing.rs`:

| Profile | Reel Stop Interval | Anticipation Duration | Rollup Speed |
|---------|--------------------|-----------------------|--------------|
| Normal | 400ms | 800ms | 1.0x |
| Turbo | 200ms | 400ms | 2.0x |
| Mobile | 350ms | 600ms | 1.2x |
| Studio | 500ms | 1000ms | 0.8x |

### Ključni Fajlovi

| Fajl | Opis |
|------|------|
| `crates/rf-slot-lab/src/spin.rs` | Stage generacija (Rust) |
| `crates/rf-slot-lab/src/timing.rs` | Timing konfiguracija |
| `flutter_ui/lib/providers/slot_lab_provider.dart` | Stage triggering |
| `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` | Spin UI + animacija |
| `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` | Reel animacija |

---

## 🎯 SLOTLAB TIMELINE DRAG SYSTEM (2026-01-21) ✅

### Arhitektura

SlotLab timeline koristi **apsolutno pozicioniranje** za layer drag operacije.

**Ključne komponente:**

| Komponenta | Fajl | Opis |
|------------|------|------|
| **TimelineDragController** | `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart` | Centralizovani state machine za drag operacije |
| **SlotLabScreen** | `flutter_ui/lib/screens/slot_lab_screen.dart` | Timeline UI sa layer renderingom |
| **MiddlewareProvider** | `flutter_ui/lib/providers/middleware_provider.dart` | Source of truth za layer.offsetMs |

### Drag Flow (Apsolutno Pozicioniranje)

```
1. onHorizontalDragStart:
   - Čita offsetMs direktno iz providera (source of truth)
   - Pretvara u sekunde: absoluteOffsetSeconds = offsetMs / 1000
   - Poziva controller.startLayerDrag(absoluteOffsetSeconds)

2. onHorizontalDragUpdate:
   - Računa timeDelta = dx / pixelsPerSecond
   - Poziva controller.updateLayerDrag(timeDelta)
   - Controller akumulira: _layerDragDelta += timeDelta

3. Vizualizacija tokom drag-a:
   - controller.getAbsolutePosition() vraća apsolutnu poziciju
   - Relativna pozicija za prikaz = absolutePosition - region.start
   - offsetPixels = relativePosition * pixelsPerSecond

4. onHorizontalDragEnd:
   - newAbsoluteOffsetMs = controller.getAbsolutePosition() * 1000
   - provider.setLayerOffset(eventId, layerId, newAbsoluteOffsetMs)
```

### Controller State

```dart
class TimelineDragController {
  double _absoluteStartSeconds;  // Apsolutna pozicija na početku drag-a
  double _layerDragDelta;        // Akumulirani delta tokom drag-a

  double getAbsolutePosition() {
    return (_absoluteStartSeconds + _layerDragDelta).clamp(0.0, infinity);
  }
}
```

### Zašto Apsolutno Pozicioniranje?

**Problem sa relativnim offsetom:**
- `layer.offset` = pozicija relativno na `region.start`
- `region.start` se dinamički menja (prati najraniji layer)
- Pri drugom drag-u, `region.start` može biti drugačiji
- Rezultat: layer "skače" na pogrešnu poziciju

**Rešenje:**
- Uvek čitaj `offsetMs` direktno iz providera
- Controller čuva apsolutnu poziciju
- Relativni offset se računa samo za vizualizaciju
- `region.start` nije uključen u drag kalkulacije

### Event Log Deduplikacija

Event Log prikazuje **jedan entry po stage-u**:
- 🎵 za stage-ove sa audio eventom
- ⚠️ za stage-ove bez audio eventa

**Implementacija:**
- `EventRegistry.triggerStage()` uvek poziva `notifyListeners()`
- Event Log sluša EventRegistry, ne SlotLabProvider direktno
- Sprečava duple entries kad se stage i audio trigeruju istovremeno

### Commits (2026-01-21)

| Commit | Opis |
|--------|------|
| `e1820b0c` | Event log deduplication + captured values pattern |
| `97d8723f` | Absolute positioning za layer drag |

---

Za detalje: `.claude/project/fluxforge-studio.md`

---

## 🔄 CI/CD Pipeline (2026-01-22) ✅

Kompletni GitHub Actions workflow za build, test i release.

**Location:** `.github/workflows/ci.yml`

### Jobs

| Job | Runner | Description |
|-----|--------|-------------|
| `check` | ubuntu-latest | Code quality (rustfmt, clippy) |
| `build` | matrix (4 OS) | Cross-platform Rust build + tests |
| `macos-universal` | macos-14 | Universal binary (ARM64 + x64) |
| `bench` | ubuntu-latest | Performance benchmarks |
| `security` | ubuntu-latest | cargo-audit security scan |
| `docs` | ubuntu-latest | Rust documentation build |
| `flutter-tests` | macos-latest | Flutter analyze + tests + coverage |
| `build-wasm` | ubuntu-latest | WASM build (wasm-pack) |
| `regression-tests` | ubuntu-latest | DSP + engine regression tests |
| `audio-quality-tests` | ubuntu-latest | Audio quality verification |
| `flutter-build-macos` | macos-14 | Full macOS app build |
| `release` | ubuntu-latest | Create release archives |

### Build Matrix

| OS | Target | Artifact |
|----|--------|----------|
| macOS 14 | aarch64-apple-darwin | reelforge-macos-arm64 |
| macOS 13 | x86_64-apple-darwin | reelforge-macos-x64 |
| Windows | x86_64-pc-windows-msvc | reelforge-windows-x64 |
| Ubuntu | x86_64-unknown-linux-gnu | reelforge-linux-x64 |

### Regression Tests

**DSP Tests:** `crates/rf-dsp/tests/regression_tests.rs` (~400 LOC)

| Test | Description |
|------|-------------|
| `test_biquad_lowpass_impulse_response` | Verifies filter impulse response |
| `test_biquad_highpass_dc_rejection` | DC offset rejection |
| `test_biquad_stability` | Numerical stability under extreme conditions |
| `test_compressor_gain_reduction` | Gain reduction accuracy |
| `test_limiter_ceiling` | True peak limiting |
| `test_gate_silence` | Gate closes to silence |
| `test_stereo_pan_law` | Equal power pan law |
| `test_stereo_width` | Width processing |
| `test_processing_determinism` | Bit-exact reproducibility |
| `test_state_independence` | Multiple instance isolation |
| `test_denormal_handling` | Denormal flushing |
| `test_coefficient_quantization` | Filter coefficient precision |
| `test_peak_detection` | Peak meter accuracy |
| `test_rms_calculation` | RMS meter accuracy |

**Total:** 39 tests (25 integration + 14 regression)

### Triggers

- Push to `main`, `develop`, `feature/**`
- Pull requests to `main`, `develop`
- Release creation
- Manual dispatch

---

## 🔬 KOMPLET ANALIZA SISTEMA — Ultimate System Review

**Trigger:** Kada korisnik kaže "komplet analiza sistema", "full system review", "ultimate analysis"

**Uloga:** Principal Engine Architect + Audio Middleware Architect + Slot Systems Designer + UX Lead

**Cilj:** Potpuna, ultimativna analiza FluxForge Studio kao:
- Profesionalni slot-audio middleware
- Authoring alat za dizajnere
- Runtime engine
- Offline DSP pipeline
- Simulacioni alat za slot igre
- Kreativni alat za audio dizajnere
- Produkcioni alat za studije

---

### FAZA 1: Analiza po ulogama (9 uloga)

Za SVAKU ulogu izvršiti:

| # | Uloga | Fokus |
|---|-------|-------|
| 1 | 🎮 Slot Game Designer | Slot layout, math, GDD, feature flow |
| 2 | 🎵 Audio Designer / Composer | Layering, states, events, mixing |
| 3 | 🧠 Audio Middleware Architect | Event model, state machines, runtime |
| 4 | 🛠 Engine / Runtime Developer | FFI, playback, memory, latency |
| 5 | 🧩 Tooling / Editor Developer | UI, workflows, batch processing |
| 6 | 🎨 UX / UI Designer | Mental models, discoverability, friction |
| 7 | 🧪 QA / Determinism Engineer | Reproducibility, validation, testing |
| 8 | 🧬 DSP / Audio Processing Engineer | Filters, dynamics, offline processing |
| 9 | 🧭 Producer / Product Owner | Roadmap, priorities, market fit |

**Za svaku ulogu odgovoriti:**

```
1. SEKCIJE: Koje delove FluxForge ta uloga koristi?
2. INPUTS: Koje podatke unosi?
3. OUTPUTS: Šta očekuje kao rezultat?
4. DECISIONS: Koje odluke donosi?
5. FRICTION: Gde se sudara sa sistemom?
6. GAPS: Šta nedostaje toj ulozi?
7. PROPOSAL: Kako poboljšati iskustvo te uloge?
```

---

### FAZA 2: Analiza po sekcijama (15+ sekcija)

Za SVAKU sekciju:

| Sekcija | Ključna pitanja |
|---------|-----------------|
| Project / Game Setup | Kako se definiše igra? Koji metapodaci? |
| Slot Layout / Mockup | Vizuelni prikaz grida, reels, simbola |
| Math & GDD Layer | Volatility, RTP, paytable integracija |
| Audio Layering System | Kako rade layer levels L1-L5? |
| Event Graph / Triggers | Stage→Event mapiranje, priority |
| Music State System | Contexts, transitions, sync modes |
| Feature Modules | FS, Bonus, Hold&Win, Cascade, Jackpot |
| Asset Manager | Import, tagging, variants, banks |
| DSP / Offline Processing | Loudness, peak limiting, format conversion |
| Runtime Adapter | Howler, Unity, Unreal, native export |
| Simulation / Preview | Synthetic engine, forced outcomes |
| Export / Manifest | JSON, binary, package structure |
| QA / Validation | Determinism, coverage, regression |
| Versioning / Profiles | Platform profiles, A/B testing |
| Automation / Batch | Scripting, CI/CD integration |

**Za svaku sekciju:**

```
1. PURPOSE: Koja je svrha?
2. INPUT: Šta prima?
3. OUTPUT: Šta proizvodi?
4. DEPENDENCIES: Od čega zavisi?
5. DEPENDENTS: Ko zavisi od nje?
6. ERRORS: Koje greške su moguće?
7. CROSS-IMPACT: Kako utiče na druge sekcije?
```

---

### FAZA 3: Horizontalna sistemska analiza

**Data Flow Analysis:**
```
Designer → FluxForge → Runtime Engine
    ↓           ↓           ↓
  Inputs    Processing   Outputs
```

**Identifikovati:**
- Gde se GUBI informacija?
- Gde se DUPLIRA logika?
- Gde se KRŠI determinizam?
- Gde je hard-coded umesto data-driven?
- Gde nedostaje "single source of truth"?

**Preporučiti:**
- Pure state machines
- Declarative layer logic
- Data-driven rule systems
- Eliminiacija if/else odluka u runtime-u

---

### FAZA 4: Obavezni deliverables

| # | Deliverable | Format |
|---|-------------|--------|
| 1 | 📐 Sistem mapa | ASCII dijagram + opis |
| 2 | 🧩 Idealna arhitektura | Authoring → Pipeline → Runtime |
| 3 | 🎛 Ultimate Layering Model | Slot-specifičan L1-L5 sistem |
| 4 | 🧠 Unified Event Model | Stage → Event → Audio chain |
| 5 | 🧪 Determinism & QA Layer | Validation, reproducibility |
| 6 | 🧭 Roadmap (M-milestones) | Prioritized phases |
| 7 | 🔥 Critical Weaknesses | Top 10 pain points |
| 8 | 🚀 Vision Statement | FluxForge kao Wwise/FMOD za slots |

---

### FAZA 5: Benchmark standardi

FluxForge mora nadmašiti:
- **Wwise** — Event model, state groups, RTPC
- **FMOD** — Layering, music system, runtime efficiency
- **Unity** — Authoring UX, preview, prototyping
- **iZotope** — DSP quality, offline processing

---

### Pravila izvršenja

1. **Ništa ne preskači** — svaka uloga, svaka sekcija
2. **Ništa ne pojednostavljuj** — inženjerski dokument, ne marketing
3. **Budi kritičan** — identifikuj slabosti bez diplomatije
4. **Budi konstruktivan** — svaka kritika ima predlog
5. **Output format:**
   - Markdown dokument u `.claude/reviews/`
   - Naziv: `SYSTEM_REVIEW_YYYY_MM_DD.md`
   - Commit nakon završetka

---

### Quick Reference — Fajlovi za analizu

```
# Core Providers
flutter_ui/lib/providers/middleware_provider.dart
flutter_ui/lib/providers/slot_lab_provider.dart
flutter_ui/lib/providers/ale_provider.dart
flutter_ui/lib/providers/stage_ingest_provider.dart

# Services
flutter_ui/lib/services/event_registry.dart
flutter_ui/lib/services/audio_playback_service.dart
flutter_ui/lib/services/service_locator.dart

# Rust Engine
crates/rf-engine/src/
crates/rf-bridge/src/
crates/rf-ale/src/
crates/rf-slot-lab/src/
crates/rf-stage/src/
crates/rf-ingest/src/
crates/rf-connector/src/

# Stage Ingest UI
flutter_ui/lib/widgets/stage_ingest/

# Architecture Docs
.claude/architecture/
.claude/domains/
```

---

**VAŽNO:** Ova analiza može trajati dugo. Koristiti Task tool za paralelizaciju gde je moguće. Rezultat mora biti production-ready dokument koji služi kao osnova za roadmap.

---

## 🔍 SLOTLAB SYSTEM ANALYSIS SUMMARY (2026-01-24)

Kompletna analiza SlotLab audio sistema — 8 task-ova, 6 dokumenata.

**Lokacija:** `.claude/analysis/`

### Analysis Documents

| Document | Focus | Status |
|----------|-------|--------|
| `AUDIO_VISUAL_SYNC_ANALYSIS_2026_01_24.md` | SlotLabProvider ↔ EventRegistry sync | ✅ VERIFIED |
| `QUICKSHEET_EVENT_CREATION_ANALYSIS_2026_01_24.md` | QuickSheet draft→commit flow | ✅ VERIFIED |
| `WIN_LINE_PRESENTATION_ANALYSIS_2026_01_24.md` | Win line coordinates, timers | ✅ VERIFIED |
| `CONTAINER_SYSTEM_ANALYSIS_2026_01_24.md` | Container FFI (~1225 LOC) | ✅ VERIFIED |
| `LOWER_ZONE_PANEL_CONNECTIVITY_ANALYSIS_2026_01_24.md` | 21 panels, all connected | ✅ VERIFIED |
| `ALE_SYSTEM_ANALYSIS_2026_01_24.md` | ALE FFI (776 LOC), 29 functions | ✅ VERIFIED |
| `AUTOSPATIAL_SYSTEM_ANALYSIS_2026_01_24.md` | AutoSpatial engine (~2296 LOC) | ✅ VERIFIED |

### Key Findings

**Audio-Visual Sync (P0.1):**
- Stage event flow: `spin()` → `_broadcastStages()` → EventRegistry → Audio
- `_lastNotifiedStages` deduplication prevents double-plays
- `notifyListeners()` at line 420 triggers EventRegistry sync

**QuickSheet Flow (P0.2):**
- `createDraft()` at `quick_sheet.dart:37` — SINGLE call point
- `commitDraft()` at `auto_event_builder_provider.dart:132` — SINGLE call point
- Bridge function `_onEventBuilderEventCreated()` at `slot_lab_screen.dart:6835`

**Container System (P1.1):**
- 40+ FFI functions in `container_ffi.rs` (~1225 LOC)
- P3D smoothing functions exist in Rust (lines 164, 171, 178)
- Dart bindings added: `containerSetBlendRtpcTarget`, `containerSetBlendSmoothing`, `containerTickBlendSmoothing`

**Lower Zone (P1.3):**
- 21 panels across 5 super-tabs (Stages, Events, Mix, DSP, Bake)
- ALL connected to real providers — NO placeholders
- Action strips call real provider methods

**Stage→Audio Chain (P2.1):**
- Path: Stage → EventRegistry.triggerStage() → _tryPlayEvent() → AudioPlaybackService
- Fallback resolution: `REEL_STOP_0` → `REEL_STOP` (generic)
- isLooping detection: `_LOOP` suffix, `MUSIC_*`, `AMBIENT_*` prefixes

**ALE System (P2.2):**
- 29 FFI functions fully implemented
- Tick loop at 16ms (`ale_provider.dart:783-806`)
- Signals: 18+ built-in (winTier, momentum, etc.)

**AutoSpatial (P2.3):**
- 24+ intent rules (`auto_spatial.dart:662-896`)
- 6 bus policies (UI, Reels, SFX, VO, Music, Ambience)
- Per-reel pan formula: `(reelIndex - 2) * 0.4`

### FFI Coverage

| System | Rust LOC | Dart Bindings | Status |
|--------|----------|---------------|--------|
| Container | ~1225 | 40+ functions | ✅ Complete |
| ALE | ~776 | 29 functions | ✅ Complete |
| AutoSpatial | ~2296 | Provider-based | ✅ Complete |
| Slot Lab | ~1200 | 20+ functions | ✅ Complete |

### Conclusion

**ALL SlotLab audio systems are FULLY OPERATIONAL:**
- Stage→Audio resolution works correctly
- Event creation via QuickSheet works correctly
- Container evaluation (Blend/Random/Sequence) works correctly
- ALE adaptive layering works correctly
- AutoSpatial panning works correctly
- Lower Zone panels all connected to real data

**No critical gaps identified.** System is production-ready.
