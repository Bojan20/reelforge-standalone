# FluxForge Studio — Sveobuhvatna Analiza Dokumentacije

**Datum:** 2026-01-19
**Verzija:** 1.0
**Autor:** Claude (Chief Architect Analysis)

---

## SADRŽAJ

1. [Analiza Uloga](#1-analiza-uloga)
2. [Analiza Arhitekture](#2-analiza-arhitekture)
3. [Međusobne Veze Sekcija](#3-međusobne-veze-sekcija)
4. [Pravilnosti i Obrasci](#4-pravilnosti-i-obrasci)
5. [Nepravilnosti i Problemi](#5-nepravilnosti-i-problemi)
6. [Slot Game Specifična Analiza](#6-slot-game-specifična-analiza)
7. [Ultimativna Poboljšanja](#7-ultimativna-poboljšanja)
8. [Zaključak](#8-zaključak)

---

## 1. ANALIZA ULOGA

### 1.1 Chief Audio Architect

**Domen:** Audio pipeline, DSP, spatial audio, mixing

**Odgovornosti:**
- Dizajn kompletnog audio grafa (6 buseva + master)
- Routing arhitektura (insert/send efekti, sidechain)
- Spatial audio sistem (panner, width, M/S processing)
- Kvalitet zvuka na nivou Cubase/Pro Tools/Wwise

**Kritične odluke:**
- Dual-path arhitektura (Real-time + Guard async lookahead)
- 64-bit double precision interno
- Sample-accurate automation

**Veza sa Slot Lab:**
- Definisanje bus strukture za slot audio (Sfx, Music, Voice, Ambience)
- Ducking matrix za automatsko utišavanje (npr. BigWin ducks Music)
- Attenuation curves za slot-specifične potrebe (Win Amount, Near Win, Combo)

**Ocena kompletnosti:** 95%
- ✅ Bus routing implementiran
- ✅ Ducking matrix funkcionalan
- ⚠️ Nedostaje: 3D positional audio za slot (budući feature)

---

### 1.2 Lead DSP Engineer

**Domen:** Filters, dynamics, SIMD optimizacija, real-time constraints

**Odgovornosti:**
- TDF-II biquad filteri za EQ (64 banda)
- Dynamics procesori (Compressor, Limiter, Gate, Expander)
- SIMD dispatch (AVX-512/AVX2/SSE4.2/NEON)
- Oversampling (1x do 16x)

**Kritične implementacije:**
```rust
// Runtime SIMD dispatch pattern
if is_x86_feature_detected!("avx512f") {
    unsafe { process_avx512(samples) }
} else if is_x86_feature_detected!("avx2") {
    unsafe { process_avx2(samples) }
}
```

**Audio Thread Pravila (SVETA):**
```
❌ ZABRANJENO:
- Heap alokacije (Vec::push, Box::new)
- Mutex/RwLock (može blokirati)
- System calls (file I/O, print)
- Panic (unwrap bez garancije)

✅ DOZVOLJENO:
- Stack alokacije
- Pre-alocirani buffers
- Atomics
- SIMD intrinsics
```

**Veza sa Slot Lab:**
- Limiter na master busu za slot audio (True Peak limiting)
- Dynamics za win celebrations (sidechain compression)
- FFT analiza za vizualizacije

**Ocena kompletnosti:** 98%
- ✅ SIMD dispatch implementiran
- ✅ Biquad TDF-II optimizovan
- ✅ Dynamics sa lookup tables

---

### 1.3 Engine Architect

**Domen:** Performance, memory management, system design

**Odgovornosti:**
- Lock-free komunikacija (rtrb ring buffers)
- Memory patterns (pre-allocation, object pooling)
- Concurrency patterns (atomic state, triple buffering)
- Zero-copy processing

**Kritični patterni:**

```rust
// Triple-Buffer State
struct TripleBuffer<T> {
    buffers: [T; 3],
    read_idx: AtomicUsize,
    write_idx: AtomicUsize,
}

// Lock-free UI↔Audio
let (producer, consumer) = RingBuffer::<ParamChange>::new(1024);
```

**Performance Targets:**
| Metric | Target | Status |
|--------|--------|--------|
| Audio latency | < 3ms @ 128 samples | ✅ |
| DSP load | < 20% @ 44.1kHz stereo | ✅ |
| GUI frame rate | 60fps minimum | ✅ |
| Memory | < 200MB idle | ✅ |
| Startup | < 2s cold start | ✅ |

**Veza sa Slot Lab:**
- Unified Playback Controller za section management
- Engine assignment (DAW engine vs SlotLab FFI)
- State persistence kroz sekcije

**Ocena kompletnosti:** 92%
- ✅ Lock-free komunikacija
- ✅ Performance targets dostignuti
- ⚠️ Nedostaje: Memory pooling za audio buffers u SlotLab

---

### 1.4 Technical Director

**Domen:** Architecture decisions, tech stack, integration

**Odgovornosti:**
- Tech stack odluke (Flutter + Rust)
- Workspace struktura (16 Rust crates)
- FFI bridge dizajn (dart:ffi → Rust)
- Build sistema (Cargo workspace + Flutter)

**Arhitektura (7 slojeva):**
```
Layer 7: Application Shell (Flutter Desktop)
Layer 6: GUI Framework (Flutter + Dart)
Layer 5: FFI Bridge (dart:ffi → Rust)
Layer 4: State Management (Dart Providers)
Layer 3: Audio Engine (Rust: rf-engine)
Layer 2: DSP Processors (Rust: rf-dsp)
Layer 1: Audio I/O (Rust: cpal)
```

**Jezici:**
- Dart: 45% (Flutter UI, state management)
- Rust: 54% (DSP, audio engine, FFI bridge)
- WGSL: 1% (GPU shaders)

**Veza sa Slot Lab:**
- rf-slot-lab crate integracija
- FFI bridge za slot_lab_spin(), slot_lab_get_stages_json()
- Provider arhitektura za SlotLabProvider

**Ocena kompletnosti:** 95%
- ✅ Čista separacija slojeva
- ✅ FFI bridge funkcionalan
- ⚠️ Nedostaje: rf-ingest crate za Universal Stage Ingest

---

### 1.5 UI/UX Expert

**Domen:** DAW workflows, pro audio UX, slot-specific UI

**Odgovornosti:**
- Custom widgets (knobs, faders, meters, waveforms)
- 120fps capable rendering (Impeller)
- Pro audio UX patterns
- Glass/Classic theme switching

**Visual Design:**
```
COLOR PALETTE — PRO AUDIO DARK:

Backgrounds:
├── #0a0a0c  (deepest)
├── #121216  (deep)
├── #1a1a20  (mid)
└── #242430  (surface)

Accents:
├── #4a9eff  (blue — focus)
├── #ff9040  (orange — active)
├── #40ff90  (green — OK)
├── #ff4060  (red — error)
└── #40c8ff  (cyan — spectrum)
```

**Slot Lab UI komponente:**
- StageTraceWidget — animated timeline kroz stage evente
- SlotPreviewWidget — premium slot machine sa animacijama
- EventLogPanel — real-time log audio eventa
- ForcedOutcomePanel — test buttons (1-0 shortcuts)
- AudioHoverPreview — browser sa hover preview

**Veza sa Slot Lab:**
- Fullscreen Slot Lab editor
- Glass timeline wrappers
- Drag smoothing za smooth interakciju

**Ocena kompletnosti:** 88%
- ✅ Glass theme implementiran
- ✅ Custom widgets funkcionalni
- ⚠️ Nedostaje: Waveform thumbnail strip za stage timeline
- ⚠️ Nedostaje: Visual feedback za REEL_SPIN loop

---

### 1.6 Graphics Engineer

**Domen:** GPU rendering, shaders, visualization

**Odgovornosti:**
- wgpu visualizacije (rf-viz)
- Skia/Impeller backend
- GPU-accelerated waveform rendering
- Spectrum analyzer (FFT → GPU)

**Implementacije:**
- Waveform GPU LOD rendering
- 60fps spectrum display
- Glass blur effects (BackdropFilter)

**Veza sa Slot Lab:**
- Reel spin animacije
- Win celebration effects
- Symbol highlight shaders

**Ocena kompletnosti:** 75%
- ✅ Basic GPU rendering
- ⚠️ Nedostaje: rf-viz wgpu integration
- ⚠️ Nedostaje: GPU particle effects za wins

---

### 1.7 Security Expert

**Domen:** Input validation, safety, repository integrity

**Odgovornosti:**
- Input validation na system boundaries
- Safety guardrails (forbidden operations)
- Repository integrity rules

**Forbidden Operations:**
```bash
❌ rm -rf (bilo gde)
❌ git reset --hard
❌ git push --force (na main/master)
❌ Brisanje .claude/ foldera
❌ Bypass audio-thread constraints
```

**Veza sa Slot Lab:**
- Validacija JSON inputa za stage evente
- Safe FFI boundary (null checks, bounds checking)
- Audit trail za forced outcomes

**Ocena kompletnosti:** 90%
- ✅ Safety guardrails definisani
- ✅ FFI boundary validation
- ⚠️ Nedostaje: Rate limiting za spin requests

---

## 2. ANALIZA ARHITEKTURE

### 2.1 Authority Hierarchy (5 nivoa)

```
LEVEL 1: Hard Non-Negotiables (HIGHEST)
├── Audio thread: lock-free, allocation-free, deterministic
├── FFI boundary: always safe, never panic
└── Security: never rm -rf, never force-push main

LEVEL 2: Engine Architecture
├── 7-layer architecture must be respected
├── Rust owns audio, Dart owns UI
└── Lock-free communication via rtrb

LEVEL 3: Definition of Done / Milestones
├── Exit criteria for each feature
├── Test coverage requirements
└── Performance benchmarks

LEVEL 4: Implementation Guides
├── DSP patterns (TDF-II, SIMD)
├── Memory patterns (pre-allocation)
└── Concurrency patterns (atomic state)

LEVEL 5: Vision Documents (LOWEST)
├── Feature ideas
├── Future plans
└── Aspirational goals
```

**Konflikt Resolution:** Viši nivo UVEK pobeđuje.

### 2.2 Build Matrix

**Rust:**
```bash
cargo build --release
cargo test
cargo clippy
cargo bench --package rf-dsp
```

**Flutter:**
```bash
flutter analyze   # MORA biti 0 errors UVEK
./scripts/run-macos.sh  # Za eksterni disk
```

**FFI Boundary Update Flow:**
```
1. Update crates/rf-bridge/src/ffi.rs
2. Run: flutter_rust_bridge_codegen generate
3. Update flutter_ui/lib/src/rust/api/native_ffi.dart
4. Update flutter_ui/lib/services/engine_api.dart
5. cargo build && flutter analyze
```

### 2.3 Slot Lab Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUTTER UI LAYER                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐   │
│  │SlotPreview  │ │StageTrace   │ │ForcedOutcomePanel       │   │
│  │Widget       │ │Widget       │ │(keyboard 1-0)           │   │
│  └──────┬──────┘ └──────┬──────┘ └───────────┬─────────────┘   │
│         │               │                     │                  │
│         └───────────────┴──────────┬──────────┘                  │
│                                    ▼                             │
│                        ┌───────────────────────┐                │
│                        │   SlotLabProvider     │                │
│                        │   - spin()            │                │
│                        │   - spinForced()      │                │
│                        │   - lastResult        │                │
│                        │   - lastStages        │                │
│                        └───────────┬───────────┘                │
├────────────────────────────────────┼────────────────────────────┤
│                    FFI BRIDGE LAYER                              │
│                        ┌───────────┴───────────┐                │
│                        │  slot_lab_ffi.rs      │                │
│                        │  - slot_lab_spin()    │                │
│                        │  - get_stages_json()  │                │
│                        └───────────┬───────────┘                │
├────────────────────────────────────┼────────────────────────────┤
│                    RUST ENGINE LAYER                             │
│                        ┌───────────┴───────────┐                │
│                        │  rf-slot-lab crate    │                │
│                        │  ┌─────────────────┐  │                │
│                        │  │SyntheticSlotEngine│ │                │
│                        │  │  - spin()        │ │                │
│                        │  │  - forced_spin() │ │                │
│                        │  └────────┬────────┘  │                │
│                        │           ▼           │                │
│                        │  ┌─────────────────┐  │                │
│                        │  │ StageGenerator  │  │                │
│                        │  │ (20+ stage types)│ │                │
│                        │  └─────────────────┘  │                │
│                        └───────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Unified Playback System

```
┌─────────────────────────────────────────────────────────────────┐
│                 UnifiedPlaybackController                        │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │   DAW    │  │ SlotLab  │  │Middleware│  │ Browser  │        │
│  │ Section  │  │ Section  │  │ Section  │  │ Section  │        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
│       │             │             │             │                │
│       └─────────────┴──────┬──────┴─────────────┘                │
│                            ▼                                     │
│                   ┌─────────────────┐                           │
│                   │ Active Section  │                           │
│                   │ (mutual exclusive)                          │
│                   └────────┬────────┘                           │
│                            ▼                                     │
│              ┌─────────────────────────────┐                    │
│              │      Engine Assignment      │                    │
│              │  DAW → rf-engine            │                    │
│              │  SlotLab → rf-slot-lab      │                    │
│              │  Middleware → provider only │                    │
│              │  Browser → just_audio       │                    │
│              └─────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. MEĐUSOBNE VEZE SEKCIJA

### 3.1 Vertikalne Veze (Sloj → Sloj)

```
Flutter UI (Layer 7)
    │
    ├── Provider calls FFI methods
    │   └── SlotLabProvider.spin() → ffi.slot_lab_spin()
    │
    ├── State updates from FFI
    │   └── ffi.slot_lab_get_stages_json() → Provider.lastStages
    │
    ▼
FFI Bridge (Layer 5)
    │
    ├── Rust function exports
    │   └── #[no_mangle] pub extern "C" fn slot_lab_spin()
    │
    ├── JSON serialization for complex data
    │   └── serde_json::to_string(&stages)
    │
    ▼
Rust Engine (Layer 3)
    │
    ├── Business logic
    │   └── SyntheticSlotEngine.spin() → SpinResult + Vec<StageEvent>
    │
    ├── DSP processing
    │   └── rf-dsp processors for audio effects
    │
    ▼
Audio I/O (Layer 1)
    │
    └── cpal audio callback
        └── Sample-accurate playback
```

### 3.2 Horizontalne Veze (Feature → Feature)

```
Slot Lab ←───────────────────→ Event Registry
    │                              │
    │  Stage events trigger        │  Maps stage → audio event
    │  audio playback              │  Multiple layers per event
    │                              │
    ▼                              ▼
Middleware System ←──────────→ DAW Engine
    │                              │
    │  Ducking matrix              │  Bus routing
    │  Blend containers            │  Insert/send effects
    │  Random containers           │  Master processing
    │                              │
    └──────────────┬───────────────┘
                   │
                   ▼
           Unified Playback
                   │
                   └── Controls which section owns playback
```

### 3.3 Cross-Cutting Concerns

```
┌─────────────────────────────────────────────────────────────────┐
│                    CROSS-CUTTING CONCERNS                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Performance ─────────────────────────────────────────────────  │
│  │  Affects ALL layers                                          │
│  │  - Audio thread: lock-free, < 3ms latency                   │
│  │  - UI: 60fps, vsync Ticker                                  │
│  │  - Memory: < 200MB idle                                     │
│                                                                  │
│  State Management ────────────────────────────────────────────  │
│  │  Provider pattern throughout                                 │
│  │  - EngineProvider (DAW state)                               │
│  │  - SlotLabProvider (slot state)                             │
│  │  - MiddlewareProvider (middleware state)                    │
│  │  - UnifiedPlaybackController (section ownership)            │
│                                                                  │
│  Theming ─────────────────────────────────────────────────────  │
│  │  Glass/Classic mode                                          │
│  │  - ThemeModeProvider                                        │
│  │  - GlassTimelineUltimateWrapper                             │
│  │  - ThemeAwareTimelineWidget                                 │
│                                                                  │
│  Error Handling ──────────────────────────────────────────────  │
│  │  Layered approach                                            │
│  │  - Rust: Result<T, Error> (never panic in audio)            │
│  │  - FFI: null checks, bounds validation                      │
│  │  - Dart: try/catch, graceful degradation                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. PRAVILNOSTI I OBRASCI

### 4.1 Konzistentni Patterni

| Pattern | Gde se koristi | Benefit |
|---------|----------------|---------|
| **Provider State** | Svi provideri | Reactive UI updates |
| **Lock-free Ring Buffer** | UI↔Audio | Zero contention |
| **JSON Serialization** | FFI complex data | Type safety |
| **Result<T, E>** | Rust error handling | No panics |
| **SIMD Dispatch** | DSP processors | Max performance |
| **Triple Buffer** | State sync | Lock-free reads |

### 4.2 Naming Conventions

```
Rust Crates:    rf-{domain}     (rf-dsp, rf-engine, rf-slot-lab)
FFI Functions:  {domain}_{action}  (slot_lab_spin, engine_play)
Dart Providers: {Domain}Provider   (SlotLabProvider, EngineProvider)
Widgets:        {Feature}Widget    (StageTraceWidget, SlotPreviewWidget)
Glass Wrappers: Glass{Component}Wrapper  (GlassClipWrapper)
```

### 4.3 File Organization

```
Consistent structure across all features:

models/          # Data models (Dart)
providers/       # State management (Dart)
widgets/         # UI components (Dart)
services/        # Business logic (Dart)
crates/rf-*/     # Rust implementation
  src/
    lib.rs       # Public API
    ffi.rs       # FFI exports (if applicable)
    {module}.rs  # Feature modules
```

### 4.4 Documentation Pattern

```
Every major system has:
1. CLAUDE.md section           # Quick reference
2. .claude/architecture/*.md   # Detailed design
3. .claude/domains/*.md        # Domain rules
4. Inline code comments        # Implementation details
```

---

## 5. NEPRAVILNOSTI I PROBLEMI

### 5.1 Identifikovani Problemi

#### Problem 1: Nedoslednost u Event Registry Triggeru

**Lokacija:** `flutter_ui/lib/services/event_registry.dart`

**Problem:** REEL_SPIN loop se trigeruje na SPIN_START ali se zaustavlja samo na REEL_STOP_4, što znači da ako spin završi pre nego što svi rilovi stanu, loop nastavlja.

**Rešenje:**
```dart
// Treba dodati explicit stop na bilo koji REEL_STOP ako je poslednji
void _onStageEvent(StageEvent event) {
  if (event.type.startsWith('REEL_STOP')) {
    final reelIndex = int.tryParse(event.type.split('_').last);
    if (reelIndex == null || reelIndex >= totalReels - 1) {
      stopEvent('REEL_SPIN');
    }
  }
}
```

---

#### Problem 2: Missing Latency Compensation za Slot Audio

**Lokacija:** `crates/rf-slot-lab/src/timing.rs`

**Problem:** TimingProfile definiše trajanje animacija ali ne latency compensation za audio playback.

**Rešenje:**
```rust
pub struct TimingProfile {
    pub anticipation_delay_ms: u32,
    pub reel_stop_interval_ms: u32,
    pub win_present_delay_ms: u32,
    // DODATI:
    pub audio_latency_compensation_ms: u32,  // Kompenzacija za audio buffer
    pub visual_audio_sync_offset_ms: i32,    // Fine-tuning sync
}
```

---

#### Problem 3: Hardcoded Stage Types

**Lokacija:** `crates/rf-slot-lab/src/stages.rs`

**Problem:** Stage types su hardkodirani kao stringovi, nema enum validation.

**Rešenje:**
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StageType {
    SpinStart,
    ReelSpin,
    ReelStop(u8),  // 0-4 for specific reel
    Anticipation,
    WinPresent,
    RollupStart,
    RollupTick,
    RollupEnd,
    BigWinTier(BigWinLevel),
    FeatureEnter,
    FeatureStep,
    FeatureExit,
    CascadeStep,
    JackpotTrigger,
    BonusEnter,
    BonusExit,
}
```

---

#### Problem 4: No Validation za Forced Outcomes

**Lokacija:** `crates/rf-bridge/src/slot_lab_ffi.rs`

**Problem:** `slot_lab_spin_forced(outcome: i32)` prima raw int bez validacije range-a.

**Rešenje:**
```rust
#[no_mangle]
pub extern "C" fn slot_lab_spin_forced(outcome: i32) -> bool {
    let forced = match outcome {
        0 => ForcedOutcome::Lose,
        1 => ForcedOutcome::SmallWin,
        2 => ForcedOutcome::BigWin,
        // ... etc
        _ => {
            log::warn!("Invalid forced outcome: {}", outcome);
            return false;
        }
    };

    match ENGINE.lock() {
        Ok(mut engine) => {
            engine.spin_forced(forced);
            true
        }
        Err(_) => false,
    }
}
```

---

#### Problem 5: Inconsistent Bus Routing Documentation

**Lokacija:** CLAUDE.md vs UNIFIED_PLAYBACK_SYSTEM.md

**Problem:** CLAUDE.md kaže "6 buses + master" ali lista samo 5 specifičnih (Sfx, Music, Voice, Ambience, Aux). Unified Playback System dokumentuje 6 buseva ali ih drugačije imenuje.

**Rešenje:** Standardizovati bus nazive:
```
1. SFX       - Sound effects (reel stops, button clicks)
2. MUSIC    - Background music, jingles
3. VOICE    - Voiceovers, callouts
4. AMBIENCE  - Ambient loops, atmosphere
5. AUX       - Auxiliary sends
6. MASTER    - Final output
```

---

#### Problem 6: Missing Glass Theme za Slot Lab Widgets

**Lokacija:** `flutter_ui/lib/widgets/slot_lab/`

**Problem:** SlotPreviewWidget i StageTraceWidget nemaju Glass theme support kao timeline widgets.

**Rešenje:** Dodati GlassSlotPreviewWrapper i GlassStageTraceWrapper po uzoru na glass_timeline_ultimate.dart.

---

#### Problem 7: No Audio Pooling u Event Registry

**Lokacija:** `flutter_ui/lib/services/event_registry.dart`

**Problem:** Svaki audio event kreira novi AudioPlayer instance. Za brze stage evente (cascade, rollup ticks) ovo može uzrokovati latency.

**Rešenje:**
```dart
class AudioPool {
  final Map<String, List<AudioPlayer>> _pool = {};
  final int _maxPerEvent = 4;

  Future<AudioPlayer> acquire(String eventId) async {
    final pool = _pool[eventId] ??= [];
    for (final player in pool) {
      if (!player.playing) {
        return player;
      }
    }
    if (pool.length < _maxPerEvent) {
      final player = AudioPlayer();
      pool.add(player);
      return player;
    }
    // Reuse oldest
    return pool.first;
  }
}
```

---

### 5.2 Dokumentacijske Neusklađenosti

| Dokument A | Dokument B | Neusklađenost |
|------------|------------|---------------|
| CLAUDE.md | SLOT_LAB_SYSTEM.md | Različiti nazivi za iste stage types |
| CLAUDE.md | engine-arch.md | Performance targets se razlikuju |
| UNIFIED_PLAYBACK | SLOT_LAB_SYSTEM | Section ownership nije jasno definisan |

---

## 6. SLOT GAME SPECIFIČNA ANALIZA

### 6.1 Trenutne Slot Mogućnosti

| Feature | Status | Kvalitet |
|---------|--------|----------|
| Synthetic Spin Engine | ✅ | Odličan |
| Stage Generation | ✅ | Dobar |
| Forced Outcomes | ✅ | Dobar |
| Event Registry | ✅ | Potrebna poboljšanja |
| Audio Triggering | ✅ | Bazičan |
| Win Tiers | ✅ | Odličan |
| Cascade Support | ✅ | Bazičan |
| Free Spins | ✅ | Bazičan |
| Jackpot System | ⚠️ | Samo trigger, nema progressive |

### 6.2 Slot-Specific Audio Workflow

```
Tipičan workflow za slot audio dizajn:

1. SPIN INITIATION
   └── Player clicks SPIN
       ├── SPIN_START stage → Button click sound
       └── REEL_SPIN stage → Reel loop starts

2. REEL RESOLUTION
   └── Reels stop sequentially
       ├── REEL_STOP_0 → First reel thud
       ├── REEL_STOP_1 → Second reel thud
       ├── ...
       └── REEL_STOP_4 → Last reel thud + REEL_SPIN loop stops

3. ANTICIPATION (optional)
   └── Near-miss or potential big win
       ├── ANTICIPATION_ON → Tension music starts
       └── ANTICIPATION_OFF → Tension resolves

4. WIN EVALUATION
   └── Server returns result
       ├── WIN_PRESENT → Win amount displays
       ├── ROLLUP_START → Counter begins
       ├── ROLLUP_TICK → Each increment
       └── ROLLUP_END → Counter stops

5. BIG WIN CELEBRATION (if applicable)
   └── Win exceeds threshold
       ├── BIGWIN_TIER_1 → Small celebration
       ├── BIGWIN_TIER_2 → Medium celebration
       ├── BIGWIN_TIER_3 → Big celebration
       └── BIGWIN_TIER_4 → Mega celebration

6. FEATURE ENTRY (if triggered)
   └── Bonus/Free Spins activated
       ├── FEATURE_ENTER → Transition sound
       ├── FEATURE_STEP → Each free spin
       └── FEATURE_EXIT → Return to base game
```

### 6.3 Nedostajuće Slot Features

| Feature | Prioritet | Kompleksnost | Opis |
|---------|-----------|--------------|------|
| **Progressive Jackpot Audio** | HIGH | Medium | Ticker sounds, contribution dings |
| **Near Miss Audio** | HIGH | Low | Suspense for almost-wins |
| **Gamble Feature** | MEDIUM | Low | Card flip sounds, risk audio |
| **Multiplier Announcements** | MEDIUM | Low | x2, x5, x10 voice callouts |
| **Scatter Collection** | MEDIUM | Low | Collect sounds for feature triggers |
| **Wild Expansion** | LOW | Medium | Animation sync for expanding wilds |
| **Reel Respin** | LOW | Low | Individual reel spin sounds |
| **Buy Feature** | LOW | Low | Purchase confirmation audio |

### 6.4 Slot Audio Quality Gaps

#### Gap 1: No Layered Win Sounds

**Problem:** Trenutno jedan zvuk po win tieru. Profesionalni slot games imaju:
- Base win sound
- + Coin shower layer (volume scales with win)
- + Music stinger layer
- + Voice callout layer

**Rešenje:** Multi-layer event system je već tu (AudioLayer), ali treba:
```dart
class WinCelebration {
  final List<AudioLayer> baseLayers;
  final List<AudioLayer> scalingLayers;  // Volume = f(winAmount)
  final List<AudioLayer> conditionalLayers;  // e.g., voice only for big wins
}
```

---

#### Gap 2: No Dynamic Music System

**Problem:** Background music ne reaguje na game state.

**Rešenje:** Music System je implementiran u Middleware, ali treba integracija:
```dart
// Na ANTICIPATION_ON:
musicSystem.transitionToSegment('tension');

// Na BIGWIN_TIER_3+:
musicSystem.playStinger('mega_win_fanfare');

// Na FEATURE_ENTER:
musicSystem.transitionToSegment('bonus_loop');
```

---

#### Gap 3: No Audio Ducking Automation

**Problem:** Manual ducking configuration. Slot games need automatic ducking.

**Rešenje:** Auto-ducking profiles:
```dart
enum SlotDuckingProfile {
  normalSpin,      // Music at 100%, SFX at 100%
  anticipation,    // Music ducked to 40%, SFX at 100%
  bigWin,          // Music ducked to 20%, SFX at 120%
  featureEntry,    // Music crossfade to feature music
}
```

---

#### Gap 4: No Positional Audio

**Problem:** Sve zvuči kao stereo center. Slot games benefit from:
- Reel sounds panned L-R based on reel position
- Win sounds with stereo width based on win line position

**Rešenje:**
```dart
class ReelStopEvent extends StageEvent {
  final int reelIndex;

  double get panPosition {
    // 5 reels: -1.0, -0.5, 0.0, 0.5, 1.0
    return (reelIndex / 4.0) * 2.0 - 1.0;
  }
}
```

---

## 7. ULTIMATIVNA POBOLJŠANJA

### 7.1 Kratkoročna (1-2 nedelje)

#### 7.1.1 Implement StageType Enum

**Fajlovi:** `crates/rf-slot-lab/src/stages.rs`, FFI, Provider

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum StageType {
    SpinStart,
    ReelSpin,
    ReelStop { reel: u8 },
    Anticipation { on: bool },
    WinPresent { amount: u64, tier: WinTier },
    Rollup { phase: RollupPhase, current: u64 },
    BigWin { tier: u8 },
    Feature { phase: FeaturePhase, data: FeatureData },
    Cascade { step: u8 },
    Jackpot { level: JackpotLevel },
}
```

#### 7.1.2 Audio Pool Implementation

**Fajl:** `flutter_ui/lib/services/audio_pool.dart`

Pre-allocate audio players za najčešće evente.

#### 7.1.3 Glass Theme za Slot Lab

**Fajlovi:** `flutter_ui/lib/widgets/glass/glass_slot_lab.dart`

Kreirati Glass wrappers za SlotPreviewWidget, StageTraceWidget, EventLogPanel.

#### 7.1.4 Latency Compensation

**Fajl:** `crates/rf-slot-lab/src/timing.rs`

Dodati audio_latency_compensation_ms u TimingProfile.

---

### 7.2 Srednjeročna (1-2 meseca)

#### 7.2.1 Universal Stage Ingest System

**Novi crates:**
- `rf-stage` — Canonical stage definitions
- `rf-ingest` — Adapter framework
- `rf-connector` — Live connection protocols

**Adapter Wizard UI:**
```
1. Import engine event log (JSON/CSV)
2. Auto-detect event patterns
3. Map events → canonical stages
4. Generate adapter code
5. Test with sample data
```

#### 7.2.2 Dynamic Music Integration

**Integracija:** MusicSystem + SlotLabProvider

```dart
class SlotMusicController {
  final MusicSystem musicSystem;

  void onStageEvent(StageEvent event) {
    switch (event.type) {
      case 'ANTICIPATION_ON':
        musicSystem.transitionToSegment('tension',
          crossfadeMs: 500);
        break;
      case 'BIGWIN_TIER_3':
      case 'BIGWIN_TIER_4':
        musicSystem.playStinger('mega_win');
        break;
      case 'FEATURE_ENTER':
        musicSystem.transitionToSegment('bonus',
          crossfadeMs: 1000);
        break;
    }
  }
}
```

#### 7.2.3 Layered Win System

**Novi model:**
```dart
class LayeredWinEvent {
  final String baseSound;
  final List<ScalingLayer> scalingLayers;
  final List<ConditionalLayer> conditionalLayers;
  final DuckingProfile ducking;
}

class ScalingLayer {
  final String sound;
  final double minWinRatio;  // Start at this win ratio
  final double maxVolume;
  final Curve volumeCurve;
}
```

#### 7.2.4 Reel Position Panning

**Implementacija:**
```dart
// U EventRegistry.trigger():
void triggerReelStop(int reelIndex) {
  final pan = _calculatePan(reelIndex, totalReels);
  trigger('REEL_STOP_$reelIndex', pan: pan);
}

double _calculatePan(int index, int total) {
  if (total <= 1) return 0.0;
  return (index / (total - 1)) * 2.0 - 1.0;
}
```

---

### 7.3 Dugoročna (3-6 meseci)

#### 7.3.1 Live Engine Connection

**Protocol:**
```
WebSocket/TCP connection to game engine
  │
  ├── Handshake (protocol version, adapter ID)
  │
  ├── Event Stream (bidirectional)
  │   ├── Engine → FluxForge: Raw events
  │   ├── FluxForge → Engine: Audio triggers (optional)
  │   └── Latency measurement packets
  │
  └── Sync Control
      ├── Time sync (NTP-style)
      └── Event buffering for jitter compensation
```

#### 7.3.2 AI-Assisted Audio Design

**Korišćenje rf-ml:**
```
1. Analyze reference slot audio
2. Extract timing patterns
3. Suggest audio placement
4. Auto-generate variations
5. Quality check (loudness, frequency balance)
```

#### 7.3.3 GPU Particle System za Wins

**Korišćenje rf-viz/wgpu:**
```rust
pub struct WinParticleSystem {
    coin_emitter: ParticleEmitter,
    sparkle_emitter: ParticleEmitter,

    pub fn trigger_win(&mut self, tier: WinTier, position: Vec2) {
        let intensity = tier.particle_intensity();
        self.coin_emitter.burst(intensity, position);
        self.sparkle_emitter.burst(intensity * 2, position);
    }
}
```

#### 7.3.4 Comprehensive Slot Audio Templates

**Template Library:**
```
templates/
├── classic_slots/
│   ├── 3_reel_fruit.json
│   └── 5_reel_video.json
├── modern_slots/
│   ├── megaways.json
│   ├── cluster_pays.json
│   └── cascading.json
├── branded_style/
│   ├── adventure.json
│   ├── mythology.json
│   └── asian.json
└── audio_packs/
    ├── coin_sounds/
    ├── reel_sounds/
    ├── win_celebrations/
    └── ambient_loops/
```

---

### 7.4 Prioritized Roadmap

```
Q1 2026:
├── Week 1-2: StageType enum + validation
├── Week 3-4: Audio pool + Glass theme
├── Week 5-6: Latency compensation
├── Week 7-8: Basic layered wins
└── Week 9-10: Testing + polish

Q2 2026:
├── Month 1: Universal Stage Ingest (offline)
├── Month 2: Dynamic music integration
└── Month 3: Reel panning + ducking automation

Q3 2026:
├── Month 1: Live engine connection (beta)
├── Month 2: AI-assisted features
└── Month 3: GPU particles + templates

Q4 2026:
├── Production hardening
├── Performance optimization
└── Documentation + tutorials
```

---

## 8. ZAKLJUČAK

### 8.1 Snage Sistema

1. **Čista Arhitektura** — 7-layer separation radi odlično
2. **Lock-free Audio** — Striktna pravila se poštuju
3. **Slot Lab Foundation** — Solidna baza za slot audio
4. **Middleware Integration** — Wwise/FMOD-style features
5. **Unified Playback** — Elegantan section management

### 8.2 Oblasti za Poboljšanje

1. **Slot-Specific Audio** — Nedostaju napredni slot features
2. **Live Integration** — Nema real-time engine connection
3. **Audio Pooling** — Potrebna optimizacija za brze evente
4. **Glass Theme Coverage** — Nedostaje za Slot Lab widgets
5. **Documentation Sync** — Neke neusklađenosti između dokumenata

### 8.3 Kritični Path za Slot Audio Excellence

```
CURRENT STATE ────────────────────────────────────────────► ULTIMATE GOAL

Basic stage triggers    →  Layered contextual audio
Manual event mapping    →  Universal Stage Ingest
Static music           →  Dynamic reactive music
Center-panned audio    →  Positional slot audio
No live connection     →  Real-time engine sync
```

### 8.4 Završna Ocena

| Aspekt | Ocena | Komentar |
|--------|-------|----------|
| **Arhitektura** | 9/10 | Odlična separacija, jasna hijerarhija |
| **DSP Quality** | 9/10 | Pro-level, SIMD optimized |
| **Slot Features** | 7/10 | Solidna baza, nedostaju napredni features |
| **Documentation** | 8/10 | Detaljna, ali ima neusklađenosti |
| **UI/UX** | 8/10 | Dobar, Glass theme potreban za Slot Lab |
| **Performance** | 9/10 | Svi targeti dostignuti |
| **Integration** | 6/10 | Offline only, nema live connection |

**Overall: 8/10** — Solidan foundation, sa jasnim putevima do excellence.

---

*Dokument generisan: 2026-01-19*
*Autor: Claude (Chief Architect Analysis)*
*Verzija: 1.0*
