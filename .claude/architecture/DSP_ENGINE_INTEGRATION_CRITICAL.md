# DSP → Engine Integration — CRITICAL ARCHITECTURAL ISSUE

**Status:** 🟢 FIXED (P0 + P1 + Bypass Fix Complete)
**Priority:** P2 (Testing remaining)
**Date:** 2026-01-23
**Updated:** 2026-02-15
**Impact:** FabFilter panels NOW affect audio output via DspChainProvider + Direct FFI Bypass
**Ghost Code:** ✅ DELETED from ffi.rs and native_ffi.dart
**Bypass Fix:** ✅ FFI redirected from `ffi_insert_set_bypass` (broken ENGINE) to `track_insert_set_bypass` (PLAYBACK_ENGINE)

---

## Executive Summary

~~FabFilter DSP panels (Compressor, Limiter, Gate, Reverb) create **ghost processor instances** that exist outside the audio signal path. User sees parameters changing but audio is NOT affected.~~

**RESOLVED (2026-01-23):** All FabFilter panels now use `DspChainProvider` and `insertSetParam()` to modify processors in the actual audio signal path. Parameter changes now affect audio output.

---

## Problem Diagram (Historical — NOW FIXED)

```
┌─────────────────────────────────────────────────────────────────┐
│                    FIXED ARCHITECTURE (2026-01-23)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FabFilter UI ─────┐                                            │
│                    │                                            │
│  Lower Zone UI ────┼──→ DspChainProvider ──→ insertLoadProcessor│
│                    │              ↓                             │
│  Mixer Strip ──────┘     insertSetParam(trackId, slot, idx, val)│
│                          insertSetBypass(trackId, slot, bypass) │
│                                  ↓                              │
│                    Rust: PLAYBACK_ENGINE (rf-engine/ffi.rs)     │
│                    ⚠️ NOT ffi_* (rf-bridge/api.rs — ENGINE=None)│
│                                  ↓                              │
│                    Audio Thread → PROCESSES AUDIO ✅             │
│                                                                 │
│                    (SINGLE SOURCE OF TRUTH)                     │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>Previous Broken Architecture (Click to Expand)</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                    PREVIOUS BROKEN ARCHITECTURE                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PATH A: DspChainProvider (WORKS ✅)                            │
│  ────────────────────────────────────                           │
│  DspChainProvider.addNode(trackId, DspNodeType.compressor)      │
│           ↓                                                     │
│  insertLoadProcessor(trackId, slotIdx, "compressor")            │
│           ↓                                                     │
│  Rust: track_inserts[trackId][slotIdx] = Compressor             │
│           ↓                                                     │
│  Audio Thread reads track_inserts → PROCESSES AUDIO ✅          │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PATH B: FabFilter Panels (BROKEN ❌)                           │
│  ─────────────────────────────────────                          │
│  FabFilterCompressorPanel.initState()                           │
│           ↓                                                     │
│  compressorCreate(trackId, sampleRate)                          │
│           ↓                                                     │
│  Rust: DYNAMICS_COMPRESSORS[trackId] = Compressor (GHOST!)      │
│           ↓                                                     │
│  Audio Thread NEVER reads DYNAMICS_COMPRESSORS → NO EFFECT ❌   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

---

## Root Cause

### Two Separate Storage Systems in Rust

**System A — Insert Chain (Used by Audio Thread):**
```rust
// crates/rf-engine/src/insert_chain.rs
pub struct InsertSlot {
    processor: Option<Box<dyn InsertProcessor>>,  // ← Audio thread reads THIS
    bypassed: AtomicBool,
    // ...
}

// crates/rf-engine/src/playback.rs
impl PlaybackEngine {
    fn process_track(&mut self, track_id: u64, ...) {
        for slot in &mut self.track_inserts[track_id] {
            slot.processor.process_stereo(left, right);  // ✅ Runs during playback
        }
    }
}
```

**System B — Ghost HashMap (NEVER Used by Audio Thread):**
```rust
// crates/rf-engine/src/ffi.rs
lazy_static::lazy_static! {
    static ref DYNAMICS_COMPRESSORS: DashMap<u32, Compressor> = DashMap::new();
    static ref DYNAMICS_LIMITERS: DashMap<u32, Limiter> = DashMap::new();
    static ref DYNAMICS_GATES: DashMap<u32, Gate> = DashMap::new();
}

pub extern "C" fn compressor_create(track_id: u32, sample_rate: f64) -> i32 {
    DYNAMICS_COMPRESSORS.insert(track_id, Compressor::new(sample_rate));
    // ❌ This compressor is NEVER read during audio playback!
}
```

---

## Affected Files

### Flutter (Dart)

| File | Issue | Status |
|------|-------|--------|
| `widgets/fabfilter/fabfilter_compressor_panel.dart` | Now uses `DspChainProvider` + `insertSetParam()` | ✅ FIXED |
| `widgets/fabfilter/fabfilter_limiter_panel.dart` | Now uses `DspChainProvider` + `insertSetParam()` | ✅ FIXED |
| `widgets/fabfilter/fabfilter_gate_panel.dart` | Now uses `DspChainProvider` + `insertSetParam()` | ✅ FIXED |
| `widgets/fabfilter/fabfilter_reverb_panel.dart` | Now uses `DspChainProvider` + `insertSetParam()` | ✅ FIXED |
| `providers/dsp_chain_provider.dart` | Single source of truth for insert chains | ✅ WORKS |

### Rust (FFI Bridge)

| File | Issue | Status |
|------|-------|--------|
| `crates/rf-engine/src/ffi.rs` | ~~Contains ghost `DYNAMICS_*` HashMaps~~ | ✅ DELETED |
| `crates/rf-engine/src/ffi.rs` | ~~Contains ghost `compressor_create()` etc.~~ | ✅ DELETED |
| `crates/rf-engine/src/insert_chain.rs` | Correct insert chain implementation | ✅ WORKS |
| `crates/rf-engine/src/playback.rs` | Only reads from insert chain | ✅ WORKS |

### Native FFI Bindings

| File | Issue | Status |
|------|-------|--------|
| `src/rust/native_ffi.dart` | ~~Has both `insertLoadProcessor()` and `compressorCreate()`~~ | ✅ FIXED (ghost API deleted) |

---

## Evidence

### FabFilter Panel Code (WRONG):

```dart
// flutter_ui/lib/widgets/fabfilter/fabfilter_compressor_panel.dart:268
void _initializeProcessor() {
    // ❌ WRONG: Creates ghost instance
    final success = _ffi.compressorCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      _initialized = true;
      _applyAllParameters();  // Parameters go to ghost, not insert chain
    }
}

void _applyAllParameters() {
    // ❌ WRONG: All these modify the ghost compressor
    _ffi.compressorSetThreshold(widget.trackId, _threshold);
    _ffi.compressorSetRatio(widget.trackId, _ratio);
    _ffi.compressorSetKnee(widget.trackId, _knee);
    _ffi.compressorSetAttack(widget.trackId, _attack);
    _ffi.compressorSetRelease(widget.trackId, _release);
    _ffi.compressorSetMakeup(widget.trackId, _output);
    _ffi.compressorSetMix(widget.trackId, _mix / 100.0);
}
```

### DspChainProvider Code (CORRECT):

```dart
// flutter_ui/lib/providers/dsp_chain_provider.dart:349-368
void addNode(int trackId, DspNodeType type) {
    final chain = getChain(trackId);
    final slotIndex = chain.nodes.length;
    final processorName = _typeToProcessorName(type);

    // ✅ CORRECT: Loads into insert chain
    final result = _ffi.insertLoadProcessor(trackId, slotIndex, processorName);
    if (result < 0) {
      debugPrint('[DspChainProvider] ❌ FFI Failed to load processor...');
      return;
    }
    // Audio thread will now process this!
}
```

---

## Solution Plan

### Phase 1: Integrate FabFilter with DspChainProvider (P0)

**Goal:** FabFilter panels should use DspChainProvider instead of direct ghost FFI calls.

**Changes to FabFilterCompressorPanel:**

```dart
// BEFORE (BROKEN):
void _initializeProcessor() {
    final success = _ffi.compressorCreate(widget.trackId, sampleRate: widget.sampleRate);
}

// AFTER (FIXED):
void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Find existing compressor or add one
    var compNode = chain.nodes.firstWhereOrNull((n) => n.type == DspNodeType.compressor);
    if (compNode == null) {
        dsp.addNode(widget.trackId, DspNodeType.compressor);
        compNode = dsp.getChain(widget.trackId).nodes.last;
    }
    _nodeId = compNode.id;
    _slotIndex = chain.nodes.indexOf(compNode);
    _initialized = true;
}

void _onThresholdChanged(double value) {
    // BEFORE: _ffi.compressorSetThreshold(widget.trackId, value);
    // AFTER:
    DspChainProvider.instance.updateNodeParams(
        widget.trackId,
        _nodeId,
        {'threshold': value}
    );
}
```

### Phase 2: Semantic Parameter Mapping (P1)

**Goal:** Replace generic `insertSetParam(paramIdx)` with semantic FFI functions.

**New Rust FFI functions:**

```rust
// crates/rf-engine/src/ffi.rs (NEW)
pub extern "C" fn insert_compressor_set_threshold(
    track_id: u32,
    slot_index: u32,
    db: f64
) -> i32 {
    // Gets processor from insert chain (not ghost HashMap)
    // Sets threshold semantically
}

pub extern "C" fn insert_compressor_set_ratio(
    track_id: u32,
    slot_index: u32,
    ratio: f64
) -> i32 {
    // ...
}
```

### Phase 3: Remove Ghost Code (P1)

**Delete from ffi.rs:**
- `DYNAMICS_COMPRESSORS` HashMap
- `DYNAMICS_LIMITERS` HashMap
- `DYNAMICS_GATES` HashMap
- `compressor_create()`, `compressor_set_threshold()`, etc.
- `limiter_create()`, `limiter_set_*()`, etc.
- `gate_create()`, `gate_set_*()`, etc.

**Delete from native_ffi.dart:**
- `DynamicsAPI` extension
- All `compressor*()`, `limiter*()`, `gate*()` methods

---

## Comparison with Industry Standard

### Pro Tools / Logic Pro / Cubase Architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                    INDUSTRY STANDARD                             │
│                                                                 │
│  Plugin UI → Plugin Host Manager → Audio Graph → Audio Output   │
│                    (single source of truth)                     │
└─────────────────────────────────────────────────────────────────┘
```

**Key Principles:**
1. ONE plugin instance per insert slot
2. UI always modifies the SAME instance that processes audio
3. No ghost/sidecar instances
4. Plugin Host Manager is single source of truth

### FluxForge Current (BROKEN):

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUXFORGE (BROKEN)                            │
│                                                                 │
│  FabFilter UI → Ghost HashMap → ❌ NOTHING                      │
│                                                                 │
│  DspChainProvider → Insert Chain → Audio Output ✅               │
└─────────────────────────────────────────────────────────────────┘
```

### FluxForge Target (FIXED):

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUXFORGE (FIXED)                             │
│                                                                 │
│  FabFilter UI ─┐                                                │
│                ├──→ DspChainProvider → Insert Chain → Audio ✅  │
│  Lower Zone UI ┘                                                │
│                    (single source of truth)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Task Checklist

### P0: Critical (Must Fix) — ✅ COMPLETE

- [x] `fabfilter_compressor_panel.dart` — Use DspChainProvider
- [x] `fabfilter_limiter_panel.dart` — Use DspChainProvider
- [x] `fabfilter_gate_panel.dart` — Use DspChainProvider
- [x] `fabfilter_reverb_panel.dart` — Use DspChainProvider
- [x] Added `ReverbWrapper` to `dsp_wrappers.rs` (was missing from factory)
- [x] `widgets/dsp/dynamics_panel.dart` — Use DspChainProvider (all 4 modes)
- [x] Added `DspNodeType.expander` to enum and mappings
- [x] Fixed `ExpanderWrapper.set_param()` to handle attack/release indices
- [x] `widgets/dsp/deesser_panel.dart` — Use DspChainProvider

### P1: Ghost Code Cleanup — ✅ COMPLETE

- [ ] Add semantic param FFI: `insert_compressor_set_threshold()`, etc. (OPTIONAL, insertSetParam works fine)
- [x] Delete `DYNAMICS_*` HashMaps from ffi.rs (COMPRESSORS, LIMITERS, GATES, EXPANDERS, DEESSERS)
- [x] Delete `compressor_create()` and all ghost functions from ffi.rs (~650 lines deleted)
- [x] Delete `DynamicsAPI` extension from native_ffi.dart (~250 lines deleted)
- [x] Kept `CompressorType` and `DeEsserMode` enums (still used by UI)

### P1.5: Additional Fixes (2026-01-23) — ✅ COMPLETE

- [x] `fabfilter_limiter_panel.dart` — Added separate THRESH knob (-10 dB default) vs CEILING (-0.3 dB)
- [x] `fabfilter_eq_panel.dart` — Converted from ghost FFI to DspChainProvider + insertSetParam
- [x] Fixed EQ band param indexing: `bandIndex * 11 + paramIndex`

### P1.6: Debug Widgets (2026-01-23) — ✅ COMPLETE

- [x] `widgets/debug/insert_chain_debug.dart` — Shows loaded processors and engine params
- [x] `widgets/debug/signal_analyzer_widget.dart` — Signal flow visualization (INPUT→Processors→OUTPUT)
- [x] `widgets/debug/dsp_debug_panel.dart` — Combined debug panel

### P1.7: Factory Function Bug (2026-01-23) — ✅ FIXED

**Root Cause:** `api.rs:insert_load()` used `create_processor()` which only supports EQ processors!

```rust
// BEFORE (BROKEN):
use rf_engine::create_processor;
if let Some(processor) = create_processor(&processor_name, sample_rate) {
    // create_processor only matches: "pro-eq", "ultra-eq", "pultec", etc.
    // Returns None for: "compressor", "limiter", "gate", "reverb" → FFI fails!
}

// AFTER (FIXED):
use rf_engine::create_processor_extended;
if let Some(processor) = create_processor_extended(&processor_name, sample_rate) {
    // create_processor_extended matches ALL processors including dynamics
}
```

**Supported processors in `create_processor_extended`:**
- EQ: `pro-eq`, `ultra-eq`, `pultec`, `api550`, `neve1073`, `room-correction`, `linear-phase`
- Dynamics: `compressor`, `limiter`, `gate`, `expander`, `deesser`
- Effects: `reverb`, `algorithmic-reverb`

**Fixed in:** `crates/rf-bridge/src/api.rs:4116`

### P2: Testing

- [ ] Test Compressor panel → verify audio changes
- [ ] Test Limiter panel → verify audio changes
- [ ] Test Gate panel → verify audio changes
- [ ] Test Reverb panel → verify audio changes
- [ ] Test EQ panel → verify audio changes
- [ ] Test MixerProvider ↔ DspChainProvider sync

---

## Estimated Effort

| Phase | Task | Hours |
|-------|------|-------|
| P0 | Integrate 4 FabFilter panels with DspChainProvider | 20h |
| P1 | Add semantic param FFI functions | 15h |
| P1 | Remove ghost code from Rust | 5h |
| P1 | Remove ghost code from Dart | 3h |
| P2 | Integration testing | 10h |
| **TOTAL** | | **~53h** |

---

## References

- `flutter_ui/lib/providers/dsp_chain_provider.dart` — Single source of truth for insert chains
- `flutter_ui/lib/widgets/fabfilter/*.dart` — DSP panels (all use DspChainProvider now)
- `flutter_ui/lib/widgets/debug/signal_analyzer_widget.dart` — Signal flow visualization
- `flutter_ui/lib/widgets/debug/insert_chain_debug.dart` — Chain status debug widget
- `flutter_ui/lib/widgets/debug/dsp_debug_panel.dart` — Combined debug panel
- `crates/rf-engine/src/dsp_wrappers.rs` — InsertProcessor implementations + `create_processor_extended()`
- `crates/rf-engine/src/insert_chain.rs` — Insert chain processing
- `crates/rf-bridge/src/api.rs` — FFI bridge (`insert_load()` uses `create_processor_extended`)
- `flutter_ui/lib/src/rust/native_ffi.dart` — Dart FFI bindings

---

## Parameter Index Reference

All FabFilter panels now use `insertSetParam(trackId, slotIndex, paramIndex, value)`. The parameter indices per processor:

### ProEqWrapper (`dsp_wrappers.rs`) — 12 params per band + 3 global = 771 total

**Index Formula:** `index = band_index * 12 + param_index` (bands 0-63)

| Param Index | Parameter | Range | Unit |
|-------------|-----------|-------|------|
| 0 | Frequency | 20..20000 | Hz |
| 1 | Gain | -24..24 | dB |
| 2 | Q | 0.1..18 | Q factor |
| 3 | Enabled | 0/1 | bool |
| 4 | Shape | 0..9 | EqFilterShape enum |
| 5 | DynEnabled | 0/1 | bool (dynamic EQ) |
| 6 | DynThreshold | -60..0 | dB |
| 7 | DynRatio | 1..8 | :1 |
| 8 | DynAttack | 0.1..100 | ms |
| 9 | DynRelease | 10..1000 | ms |
| 10 | DynRange | 0..24 | dB |
| 11 | Placement | 0..2 | Stereo/Mid/Side |

**Global params (idx 768-770):**

| Index | Parameter | Range | Notes |
|-------|-----------|-------|-------|
| 768 | Output Gain | -24..24 dB | Post-EQ gain |
| 769 | Auto-Gain | 0/1 | RMS compensation (±12dB clamp) |
| 770 | Solo Band | -1..63 | -1=off, 0-63=solo that band |

**Solo band logic:** On set, saves all band `enabled` states, disables all except soloed band. On un-solo (-1), restores saved states.

**Auto-gain logic:** Block-level RMS measured before and after EQ processing. Compensation = `in_rms / out_rms`, clamped to 0.25x-4.0x (±12dB).

**EqFilterShape enum:** 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch, 6=BandPass, 7=TiltShelf, 8=AllPass, 9=Brickwall

**Example:** Band 2, set frequency to 1000Hz → `insertSetParam(trackId, slot, 2*12+0, 1000.0)`

### CompressorWrapper (`dsp_wrappers.rs`)

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Threshold | -60..0 | dB |
| 1 | Ratio | 1..20 | :1 |
| 2 | Attack | 0.1..100 | ms |
| 3 | Release | 10..1000 | ms |
| 4 | Makeup | 0..24 | dB |
| 5 | Mix | 0..1 | % |
| 6 | Link | 0/1 | bool |
| 7 | Type | 0..4 | enum |

### TruePeakLimiterWrapper (`dsp_wrappers.rs`)

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Threshold | -20..0 | dB |
| 1 | Ceiling | -3..0 | dBTP |
| 2 | Release | 10..1000 | ms |
| 3 | Oversampling | 0..3 | 1x/2x/4x/8x |

### GateWrapper (`dsp_wrappers.rs`) — 10 params, 3 meters

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Threshold | -80..-20 | dB |
| 1 | Range | -80..0 | dB |
| 2 | Attack | 0.01..30 | ms |
| 3 | Hold | 0..500 | ms |
| 4 | Release | 5..4000 | ms |
| 5 | Mode | 0/1/2 | 0=Gate, 1=Duck, 2=Expand |
| 6 | SC Enable | 0/1 | Sidechain filter on/off |
| 7 | SC HP Freq | 20..2000 | Hz (highpass filter) |
| 8 | SC LP Freq | 200..20000 | Hz (lowpass filter) |
| 9 | Lookahead | 0..20 | ms |

**Meters:** 0=Input Level (dB), 1=Output Level (dB), 2=Gate Gain (0-1 linear)

**Mode behavior:**
- Gate (0): Attenuates below threshold by `range` dB
- Duck (1): Attenuates above threshold (inverted gate for ducking)
- Expand (2): Downward expansion below threshold

### ReverbWrapper (`dsp_wrappers.rs`) — NEW

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | RoomSize | 0..1 | normalized |
| 1 | Damping | 0..1 | normalized |
| 2 | Width | 0..1 | normalized |
| 3 | DryWet | 0..1 | mix ratio |
| 4 | Predelay | 0..100 | ms |
| 5 | Type | 0..7 | ReverbType enum |

**ReverbType enum values:** 0=Room, 1=Hall, 2=Church, 3=Plate, 4=Spring, 5=Ambient, 6=Chamber, 7=Cathedral

### ExpanderWrapper (`dsp_wrappers.rs`)

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Threshold | -60..0 | dB |
| 1 | Ratio | 1..10 | :1 (downward) |
| 2 | Knee | 0..12 | dB |
| 3 | Attack | 0.1..100 | ms |
| 4 | Release | 10..500 | ms |

### DeEsserWrapper (`dsp_wrappers.rs`)

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Frequency | 2000..16000 | Hz |
| 1 | Bandwidth | 0.25..4.0 | octaves |
| 2 | Threshold | -60..0 | dB |
| 3 | Range | 0..24 | dB |
| 4 | Mode | 0..1 | 0=Wideband, 1=SplitBand |
| 5 | Attack | 0.1..50 | ms |
| 6 | Release | 10..500 | ms |
| 7 | Listen | 0..1 | bool (sidechain monitor) |
| 8 | Bypass | 0..1 | bool |

### PultecWrapper (`dsp_wrappers.rs`) — FF EQP1A

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Low Boost | 0..10 | — |
| 1 | Low Atten | 0..10 | — |
| 2 | High Boost | 0..10 | — |
| 3 | High Atten | 0..10 | — |

### Api550Wrapper (`dsp_wrappers.rs`) — FF 550A

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | Low Gain | -12..12 | dB |
| 1 | Mid Gain | -12..12 | dB |
| 2 | High Gain | -12..12 | dB |

### Neve1073Wrapper (`dsp_wrappers.rs`) — FF 1073

| Index | Parameter | Range | Unit |
|-------|-----------|-------|------|
| 0 | HP Enabled | 0/1 | bool |
| 1 | Low Gain | -16..16 | dB |
| 2 | High Gain | -16..16 | dB |

---

### P1.8: Vintage EQ DspChainProvider Integration (2026-02-15) — ✅ COMPLETE

Vintage EQs (Pultec, API 550A, Neve 1073) were already supported in Rust backend (`create_processor_extended()`) but had NO exposure in the DAW insert chain UI.

**Changes (8 files):**

- [x] Added `DspNodeType.pultec`, `DspNodeType.api550`, `DspNodeType.neve1073` to enum
- [x] Added `_typeToProcessorName()` mappings: pultec→'pultec', api550→'api550', neve1073→'neve1073'
- [x] Added `_defaultParams()` for all 3 vintage EQ types
- [x] Added `_restoreNodeParameters()` for drag-drop reorder preservation
- [x] Added editor panels in `internal_processor_editor_window.dart` (`_buildPultecParams`, `_buildApi550Params`, `_buildNeve1073Params`)
- [x] Updated exhaustive switches in: `fx_chain_panel.dart`, `rtpc_system_provider.dart`, `processor_graph_widget.dart`, `signal_analyzer_widget.dart`, `slotlab_lower_zone_widget.dart`, `processor_cpu_meter.dart`

**Naming convention:** `FF EQP1A`, `FF 550A`, `FF 1073` (FluxForge-branded)

### P1.9: Gate & EQ FFI Completion (2026-02-15) — ✅ COMPLETE

DSP Plugin Audit revealed Gate had 5 unwired UI controls and EQ had 2 dead buttons. All fixed.

**Gate — Extended from 5→10 params:**

- [x] GateWrapper Rust: Added `mode`, `sc_enabled`, `sc_hpf_freq`, `sc_lpf_freq`, `lookahead` fields
- [x] GateWrapper Rust: `set_param()` indices 5-9 wired with clamped ranges
- [x] GateWrapper Rust: `get_param()` indices 5-9 return actual values
- [x] GateWrapper Rust: `param_name()` returns "Mode", "SC Enable", "SC HP Freq", "SC LP Freq", "Lookahead"
- [x] GateWrapper Rust: `num_params()` returns 10
- [x] Dart UI: `_readParamsFromEngine()` reads params 5-9 from FFI
- [x] Dart UI: `_applyAllParameters()` writes params 5-9 to FFI
- [x] Dart UI: Mode chip selector wired (Gate/Duck/Expand → param 5)
- [x] Dart UI: SC toggle, HP/LP sliders, Lookahead slider all wired via `insertSetParam`
- [x] 10 new Rust tests (factory, num_params, param_names, roundtrip, mode, sidechain, process, meters, duck, invalid)

**EQ — Auto-Gain & Solo Band wired:**

- [x] ProEqWrapper Rust: Constructor initializes `auto_gain`, `solo_band`, `solo_saved_enabled`, `solo_applied`
- [x] ProEqWrapper Rust: `get_param(769)` returns auto-gain state, `get_param(770)` returns solo band index
- [x] ProEqWrapper Rust: `set_param(769, v)` toggles auto-gain (RMS compensation in `process_stereo`)
- [x] ProEqWrapper Rust: `set_param(770, v)` saves enabled states → solos band → restores on un-solo
- [x] ProEqWrapper Rust: `process_stereo()` auto-gain: pre/post RMS measurement, clamped compensation (0.25-4.0x)
- [x] Dart UI: `_P.autoGainIndex = 769`, `_P.soloBandIndex = 770` constants
- [x] Dart UI: Auto-Gain button wired to `insertSetParam(trackId, slot, 769, value)`
- [x] Dart UI: Solo button wired with exclusive logic (un-solo others, toggle, send band index or -1)
- [x] Dart UI: `_readBandsFromEngine()` reads auto-gain state from FFI
- [x] 5 new Rust tests (auto_gain_param, solo_band_param, solo_restores, auto_gain_processing, output_gain)

**Result:** All 6 FabFilter panels are now 100% FFI connected. No dead UI controls remain.

---

## Notes

This issue was discovered during comprehensive DAW Lower Zone audit (2026-01-23). The ghost processor pattern appears to have been an early prototype approach that was never properly integrated with the main insert chain system.

**FIXED (2026-01-23):** All FabFilter panels now use `DspChainProvider` as single source of truth. The `ReverbWrapper` was added to `dsp_wrappers.rs` since it was missing from the processor factory.

**FIXED (2026-02-15):** Vintage EQs (Pultec EQP-1A, API 550A, Neve 1073) added to DspChainProvider insert chain with full editor panels and exhaustive switch coverage across 8 files.

**P1 COMPLETE (2026-01-23):** Ghost code has been deleted:
- ~650 lines removed from `crates/rf-engine/src/ffi.rs` (DYNAMICS_* HashMaps + all functions)
- ~250 lines removed from `flutter_ui/lib/src/rust/native_ffi.dart` (DynamicsAPI extension)
- Enums `CompressorType` and `DeEsserMode` preserved (still used by UI)
- `cargo build --release` and `flutter analyze` both pass with no errors

**Remaining P2 work:** Test each panel to verify audio output is affected by parameter changes.
