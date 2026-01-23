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
| 4 | `DuckingService`, `RtpcModulationService`, `ContainerService` | Audio processing |
| 5 | `StateGroupsProvider`, `SwitchGroupsProvider`, `RtpcSystemProvider`, `DuckingSystemProvider`, `EventSystemProvider`, `CompositeEventSystemProvider` | Middleware subsystems |
| 6 | `StageIngestProvider` | Stage Ingest (engine integration) |

### Subsystem Providers (extracted from MiddlewareProvider)

| Provider | File | LOC | Manages |
|----------|------|-----|---------|
| `StateGroupsProvider` | `providers/subsystems/state_groups_provider.dart` | ~185 | Global state groups (Wwise-style) |
| `SwitchGroupsProvider` | `providers/subsystems/switch_groups_provider.dart` | ~210 | Per-object switches |
| `RtpcSystemProvider` | `providers/subsystems/rtpc_system_provider.dart` | ~350 | RTPC definitions, bindings, curves |
| `DuckingSystemProvider` | `providers/subsystems/ducking_system_provider.dart` | ~190 | Ducking rules (sidechain matrix) |
| `EventSystemProvider` | `providers/subsystems/event_system_provider.dart` | ~330 | MiddlewareEvent CRUD, FFI sync |
| `CompositeEventSystemProvider` | `providers/subsystems/composite_event_system_provider.dart` | ~1280 | SlotCompositeEvent CRUD, undo/redo, layer ops, stage triggers |

**Decomposition Progress:**
- Phase 1 ✅: StateGroups + SwitchGroups
- Phase 2 ✅: RTPC + Ducking
- Phase 3 ✅: Containers (Blend/Random/Sequence providers)
- Phase 4 ✅: Music + Events (MusicSystemProvider, EventSystemProvider, CompositeEventSystemProvider)

**Usage in MiddlewareProvider:**
```dart
MiddlewareProvider(this._ffi) {
  _stateGroupsProvider = sl<StateGroupsProvider>();
  _switchGroupsProvider = sl<SwitchGroupsProvider>();
  _rtpcSystemProvider = sl<RtpcSystemProvider>();
  _duckingSystemProvider = sl<DuckingSystemProvider>();

  // Forward notifications from subsystems
  _stateGroupsProvider.addListener(notifyListeners);
  _switchGroupsProvider.addListener(notifyListeners);
  _rtpcSystemProvider.addListener(notifyListeners);
  _duckingSystemProvider.addListener(notifyListeners);
}
```

**Dokumentacija:**
- `.claude/SYSTEM_AUDIT_2026_01_21.md` — P0.2 progress
- `.claude/architecture/MIDDLEWARE_DECOMPOSITION.md` — Full decomposition plan

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

**Key Files:**
- `ultimate_mixer.dart` — Main mixer widget (~2167 LOC)
- `daw_lower_zone_widget.dart` — Full MixerProvider integration
- `glass_mixer.dart` — Thin wrapper (ThemeAwareMixer)
- `mixer_provider.dart` — Added `toggleAuxSendPreFader()`, `setAuxSendDestination()`, `setInputGain()`

**Deleted Files:**
- `pro_daw_mixer.dart` — Removed (~1000 LOC duplicate)

**Import Pattern (namespace conflict fix):**
```dart
import '../widgets/mixer/ultimate_mixer.dart' as ultimate;
// Use: ultimate.UltimateMixer, ultimate.ChannelType.audio, etc.
```

**Dokumentacija:** `.claude/architecture/ULTIMATE_MIXER_INTEGRATION.md`

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

### P2 Status Summary (2026-01-23)

**Completed: 21/22 (95%)**

| Task | Status | Note |
|------|--------|------|
| P2.1 | ✅ | SIMD metering via rf-dsp |
| P2.2 | ✅ | SIMD bus summation |
| P2.3 | ✅ | External Engine Integration (Stage Ingest, Connector FFI) |
| P2.4 | ✅ | Stage Ingest System (6 widgets, 2500 LOC) |
| P2.5 | ✅ | QA Framework (14 regression tests in rf-dsp) |
| P2.6 | ✅ | Offline DSP Backend (~2900 LOC) |
| P2.7 | ✅ | Plugin Hosting PDC (FFI bindings complete) |
| P2.8 | ✅ | MIDI Editing System (MIDI I/O FFI) |
| P2.9 | ✅ | Soundbank Building System |
| P2.10 | ✅ | Music System stinger UI (1227 LOC) |
| P2.11 | ✅ | Bounce Panel (DawBouncePanel) |
| P2.12 | ✅ | Stems Panel (DawStemsPanel) |
| P2.13 | ✅ | Archive Panel (_buildCompactArchive) |
| P2.14 | ✅ | SlotLab Batch Export |
| P2.15 | ✅ | Waveform downsampling (2048 max) |
| P2.17 | ✅ | Composite events limit (500 max) |
| P2.18 | ✅ | Container Storage Metrics (FFI) |
| P2.19 | ✅ | Custom Grid Editor (GameModelEditor) |
| P2.20 | ✅ | Bonus Game Simulator + FFI |
| P2.21 | ✅ | Audio Waveform Picker Dialog |
| P2.22 | ✅ | Schema Migration Service |

**Skipped: 1**
- P2.16 — VoidCallback not serializable, needs full refactor

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
- `premium_slot_preview.dart` — **NEW** Fullscreen premium UI sa svim elementima
- `stage_trace_widget.dart` — Animated timeline kroz stage evente
- `slot_preview_widget.dart` — Premium slot machine sa animacijama
- `event_log_panel.dart` — Real-time log audio eventa
- `forced_outcome_panel.dart` — Test buttons (keyboard shortcuts 1-0)
- `audio_hover_preview.dart` — Browser sa hover preview

**Premium Preview Mode (2026-01-21):**
```
A. Header Zone — Menu, logo, balance, VIP, audio, settings, exit
B. Jackpot Zone — 4-tier tickers (Mini/Minor/Major/Grand) + contribution meter
C. Main Game Zone — Reels, paylines, win overlay, anticipation, particles
D. Win Presenter — Rollup animation, tier badges, coin particles, collect/gamble
E. Feature Indicators — Free spins, bonus meter, multiplier, cascade
F. Control Bar — Lines/Coin/Bet selectors, Max Bet, Auto-spin, Turbo, Spin
G. Info Panels — Paytable, rules, history, stats (left side)
H. Audio/Visual — Volume slider, music/sfx toggles, quality, animations
```

**Forced Outcomes:**
```
1-Lose, 2-SmallWin, 3-BigWin, 4-MegaWin, 5-EpicWin,
6-FreeSpins, 7-JackpotGrand, 8-NearMiss, 9-Cascade, 0-UltraWin
```

**Dokumentacija:** `.claude/architecture/SLOT_LAB_SYSTEM.md`

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
