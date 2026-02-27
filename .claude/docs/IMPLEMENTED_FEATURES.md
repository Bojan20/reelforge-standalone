## 📊 IMPLEMENTED FEATURES STATUS

### Core Engine
- ✅ Audio I/O (cpal, CoreAudio/ASIO)
- ✅ Graph-based routing (topological sort)
- ✅ Lock-free parameter sync (rtrb)
- ✅ Sample-accurate playback
- ✅ Metronome / Click Track (sample-accurate, 14 FFI functions, pro settings popup)

### DSP
- ✅ 64-band Unified EQ — ProEq superset (SVF + MZT + Oversampling + Saturation + Transient-Aware)
- ✅ Dynamics (Compressor, Limiter, Gate, Expander)
- ✅ Reverb (convolution + algorithmic)
- ✅ Spatial (Panner, Width, M/S)
- 📋 Stereo Imager (exists but DISCONNECTED — fix planned, iZotope Ozone Imager level)
- 📋 Haas Delay (new — precedence effect widening)
- 📋 MultibandStereoImager (4-band, stereoize, vectorscope)
- ✅ Analysis (FFT, LUFS, True Peak, Correlation, Frequency)

### Unified FaderCurve — All Volume Controls (2026-02-21) ✅

**Single source of truth:** `FaderCurve` class in `flutter_ui/lib/utils/audio_math.dart`

ALL 11 volume faders, knobs, and dB formatters use this one class. No inline curve code anywhere.

**API:**

| Method | Input → Output | Usage |
|--------|----------------|-------|
| `FaderCurve.dbToPosition(db)` | dB → 0.0–1.0 | dB-domain faders |
| `FaderCurve.positionToDb(pos)` | 0.0–1.0 → dB | dB-domain drag |
| `FaderCurve.linearToPosition(vol)` | amplitude → 0.0–1.0 | Linear-domain faders |
| `FaderCurve.positionToLinear(pos)` | 0.0–1.0 → amplitude | Linear-domain drag |
| `FaderCurve.linearToDbString(vol)` | amplitude → "-12.3" | Display |
| `FaderCurve.dbToString(db)` | dB → "-12.3" | Display |

**Current Curve (5-segment, Cubase-style):**

| Segment | dB Range | Fader Travel | Resolution |
|---------|----------|--------------|------------|
| Silence | -∞ to -60 dB | 0–5% | Dead zone |
| Low | -60 to -20 dB | 5–25% | Compressed |
| Build-up | -20 to -6 dB | 25–55% | 30% travel for 14 dB |
| Sweet spot | -6 to 0 dB | 55–75% | 20% travel for 6 dB |
| Boost | 0 to +max dB | 75–100% | Post-unity boost |

**Planned Upgrade — Ultimate Hybrid Curve (Neve/SSL/Harrison-class):**

| Zona | dB raspon | Hod | Razlog |
|------|-----------|-----|--------|
| Dead zone | -∞ do -60 dB | 0–3% | Nečujno, minimalan prostor |
| Low | -60 do -20 dB | 3–20% | Kompresovana, nije mixing zona |
| Build-up | -20 do -12 dB | 20–40% | Priprema za sweet spot |
| **Sweet spot** | **-12 do 0 dB** | **40–78%** | **38% hoda za 12 dB** |
| Boost | 0 do +12 dB | 78–100% | Retko treba preciznost |

Key differences: 0 dB at 78% (vs 75%), sweet spot from -12 dB (vs -6 dB), dead zone 3% (vs 5%).

**11 Widgets Using FaderCurve:**

| Widget | File | Domain |
|--------|------|--------|
| `_FaderWithMeter` | `ultimate_mixer.dart` | Amplitude (0.0–1.5) |
| `_VerticalFader` | `channel/channel_strip.dart` | dB (-60 to +12) |
| `_FaderRow` | `channel_inspector_panel.dart` | dB (parameterized) |
| `ChannelStripModel` | `mixer/channel_strip.dart` | dB (faderDb getter) |
| `_BusStrip` | `slotlab_bus_mixer.dart` | Amplitude (0.0–1.0) |
| `_MiniFader` | `mini_mixer_panel.dart` | Amplitude (0.0–1.5) |
| `_MiniChannelStrip` | `mini_mixer_view.dart` | Amplitude (0.0–1.5) |
| `MixerUndoAction` | `mixer_undo_actions.dart` | Display only |
| Event Editor | `event_editor_panel.dart` | Display only |
| DAW Lower Zone | `daw_lower_zone_widget.dart` | Display only |
| Clip Properties | `clip_properties_panel.dart` | Display only |

**VAŽNO:** Kada menjaš volume krivu, menjaj SAMO `FaderCurve` klasu — svi widgeti automatski koriste novu krivu.

### Meter Decay & Noise Floor Gate (2026-02-16) ✅

Meters smoothly decay to complete invisibility (Cubase behavior).

**Implementation:** `_FaderWithMeter` in `ultimate_mixer.dart`
- Noise floor gate at **-80 dB** — below this, meter bar width = 0
- Smooth decay via existing animation (no visual jump at gate threshold)
- Applies to both peak meters in mixer channel strips

### Stereo Imager + Haas Delay + MultibandImager (2026-02-22) 📋 PLANNED

**Specifikacija:** `.claude/architecture/HAAS_DELAY_AND_STEREO_IMAGER.md`
**Target:** iZotope Ozone Imager level ili bolji

**3 Feature-a:**

| Feature | Tip | Svrha | Status |
|---------|-----|-------|--------|
| **StereoImager** | Channel strip + Insert | M/S width, balance, rotation, correlation | ❌ EXISTS but DISCONNECTED |
| **Haas Delay** | Insert processor | Precedence effect widening (1-30ms) | 📋 NEW |
| **MultibandStereoImager** | Insert processor | 4-band width, stereoize, vectorscope | 📋 NEW |

**StereoImager DISCONNECT:** `STEREO_IMAGERS` HashMap u `ffi.rs:9557` — 15+ FFI funkcija postoje ali `playback.rs` ih NIKADA NE POZIVA. Identičan bug pattern kao prethodni `DYNAMICS_COMPRESSORS`.

**Signal Flow pozicija (SSL kanonski):**
```
Input → Pre-Fader Inserts → Fader → Pan → ★ STEREO IMAGER → Post-Fader Inserts (incl. Haas) → Sends → Bus
```

**Implementacija — 45 tasks, ~5,260 LOC, 6 faza:**

| Phase | Focus | Tasks | LOC |
|-------|-------|-------|-----|
| 1 | StereoImager Fix (connect to PLAYBACK_ENGINE) | 12 | ~440 |
| 2 | Haas Delay (DSP + UI) | 7 | ~810 |
| 3 | FF-IMG Panel (StereoImager insert UI) | 3 | ~570 |
| 4 | MultibandStereoImager — iZotope Ozone Level | 12 | ~1,770 |
| 5 | Vectorscope & Metering | 4 | ~970 |
| 6 | Testing & Polish | 7 | ~700 |

**iZotope Parity + Beyond:**
- 4-band multiband width (Ozone standard)
- Stereoize allpass-chain decorrelation (mono→stereo)
- 3-mode Vectorscope (Polar Sample, Polar Level, Lissajous)
- **FluxForge exclusive:** Channel strip integration, Haas mode, stereo rotation, M/S gain

**Key Rust Structs (planned):**
- `HaasDelay` — ring buffer, LP filter, feedback, 7 params
- `MultibandStereoImager` — 4×BandImager + LinkwitzRiley crossovers + Stereoize
- `StereoImagerWrapper` — InsertProcessor (8 params)
- `HaasDelayWrapper` — InsertProcessor (7 params)
- `MultibandImagerWrapper` — InsertProcessor (17 params)

**Key Dart Files (planned):**
- `fabfilter_haas_panel.dart` — FF-HAAS (zone indicator, correlation bar)
- `fabfilter_imager_panel.dart` — FF-IMG (width, M/S, rotation, correlation)
- `fabfilter_multiband_imager_panel.dart` — FF-MBI (4-band, crossovers, stereoize)
- `vectorscope_widget.dart` — 3-mode vectorscope display

### DSP Processor Defaults Fix (2026-02-16) ✅

Processors now start **enabled** (audible) when loaded into insert chain.

**Root Cause:** `DspChainProvider.addNode()` created nodes with `bypass: true` (silent by default).

**Fix:** Changed defaults in two locations:
- `dsp_chain_provider.dart` — `DspNode()` constructor: `bypass: false`
- `fabfilter_panel_base.dart` — `_isBypassed` initial value: `false`

**4 FFI Functions Rebound (2026-02-16):**

| Old (rf-bridge, BROKEN) | New (rf-engine, WORKS) |
|-------------------------|------------------------|
| `ffi_insert_set_mix` | `track_insert_set_mix` |
| `ffi_insert_get_mix` | `track_insert_get_mix` |
| `ffi_insert_bypass_all` | `track_insert_bypass_all` |
| `ffi_insert_get_total_latency` | `track_insert_get_total_latency` |

### FabFilter-Style Premium DSP Panels (2026-01-22, Updated 2026-02-21) ✅

Professional DSP panel suite inspired by FabFilter's design language — **9 panels total**, all with A/B snapshots.

**Location:** `flutter_ui/lib/widgets/fabfilter/`

**UI Naming Convention:** `FF-X` (short) / `FF-X Name` (full) — e.g., `FF-Q` / `FF-Q 64`, `FF-C` / `FF Compressor`

| Panel | UI Name | Inspiration | Features | FFI | A/B |
|-------|---------|-------------|----------|-----|-----|
| `fabfilter_eq_panel.dart` | FF-Q 64 | Pro-Q 3 | 8-band parametric, I/O metering, spectrum, shapes | ✅ | ✅ EqSnapshot (66 fields) |
| `fabfilter_compressor_panel.dart` | FF-C | Pro-C 2 | Transfer curve, knee display, 14 styles, sidechain EQ | ✅ | ✅ CompressorSnapshot (15 fields) |
| `fabfilter_limiter_panel.dart` | FF-L | Pro-L 2 | LUFS metering, 8 styles, true peak, GR history | ✅ | ✅ LimiterSnapshot (6 fields) |
| `fabfilter_gate_panel.dart` | FF-G | Pro-G | State indicator, threshold viz, hysteresis, sidechain filter | ✅ | ✅ GateSnapshot (16 fields) |
| `fabfilter_reverb_panel.dart` | FF-R | Pro-R | Decay display, pre-delay, 8 space types, EQ | ✅ | ✅ ReverbSnapshot (11 fields) |
| `fabfilter_deesser_panel.dart` | FF-E | Pro-DS | Frequency display, listen mode, 8 params | ✅ | ✅ DeEsserSnapshot (8 fields) |
| `fabfilter_saturation_panel.dart` | FF-SAT | Saturn 2 | 6-band multiband, per-band drive/type/dynamics, crossover | ✅ | ✅ SaturationSnapshot (65 fields) |
| `fabfilter_delay_panel.dart` | FF-DLY | Timeless 3 | Ping-pong, tempo sync, mod, filter, duck, freeze | ✅ | ✅ DelaySnapshot (14 fields) |
| `fabfilter_haas_panel.dart` | FF-HAAS | — | Haas delay widener, zone indicator, LP filter, correlation | 📋 | 📋 PLANNED |
| `fabfilter_imager_panel.dart` | FF-IMG | — | Width, M/S, balance, rotation, correlation, vectorscope | 📋 | 📋 PLANNED |
| `fabfilter_multiband_imager_panel.dart` | FF-MBI | Ozone Imager | 4-band width, stereoize, crossovers, vectorscope | 📋 | 📋 PLANNED |

**DSP Sub-Panels (FabFilter Style):**

| Panel | Location | Features | FFI |
|-------|----------|----------|-----|
| `sidechain_panel.dart` | `widgets/dsp/` | FabFilter knobs (FREQ/Q/MIX/GAIN), source selector (INT/TRK/BUS/EXT/MID/SIDE), key filter (HPF/LPF/BPF), monitor toggle | ✅ sidechainSet* |

**A/B Snapshot Pattern:**
- All panels implement `DspParameterSnapshot` interface: `copy()` + `equals()`
- `FabFilterPanelMixin` provides: `captureSnapshot()`, `restoreSnapshot()`, `copyAToB()`, `copyBToA()`, `snapshotA`, `snapshotB`
- Snapshot classes capture ALL panel state (knob values, toggles, modes)
- `copy()` returns `DspParameterSnapshot` (interface) — callers MUST cast: `snapshot.copy() as EqSnapshot?`

**Shared Components:**
- `fabfilter_theme.dart` — Colors, gradients, text styles
- `fabfilter_knob.dart` — Pro knob with modulation ring, fine control, conditional label rendering
- `fabfilter_panel_base.dart` — A/B comparison, undo/redo, bypass, snapshot management
- `fabfilter_preset_browser.dart` — Categories, search, favorites
- `fabfilter_widgets.dart` — 11 reusable widgets (FabTinyButton, FabCompactToggle, FabSectionLabel, etc.)

**Total:** ~7,200 LOC

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

### 🟢 FabFilter Panels → DspChainProvider Integration (2026-01-23, Updated 2026-02-15) ✅

**Status:** FIXED — All DSP panels now use DspChainProvider + InsertProcessor chain.

**Architecture (Correct):**
```
UI Panel → DspChainProvider.addNode() → insertLoadProcessor() → track_inserts → Audio Thread ✅
         → insertSetParam(trackId, slotIndex, paramIndex, value) → Real-time parameter updates ✅
         → insertSetBypass(trackId, slotIndex, bypass) → Direct FFI bypass ✅ (Fixed 2026-02-15)
```

**Bypass FFI Fix (2026-02-15) — CRITICAL:**

**Problem:** Bypass toggle had no audible effect even with EQ bands engaged.

**Root Cause:** TWO SEPARATE ENGINE GLOBALS exist in the codebase:
1. `PLAYBACK_ENGINE` (rf-engine/ffi.rs) — `lazy_static`, **always initialized** ✅
2. `ENGINE` (rf-bridge/lib.rs) — `Option<EngineBridge>`, starts as **None** ❌

`insertLoadProcessor` and `insertSetParam` correctly used `PLAYBACK_ENGINE`, but `insertSetBypass` was calling `ffi_insert_set_bypass` in rf-bridge which used the uninitialized `ENGINE`.

**Fix:** Redirected Dart FFI binding to `track_insert_set_bypass` in rf-engine/ffi.rs:
```dart
// BEFORE (wrong — rf-bridge ENGINE, never initialized):
_insertSetBypass = _lib.lookupFunction<...>('ffi_insert_set_bypass');
typedef InsertSetBypassNative = Void Function(Uint64 trackId, Uint32 slot, Int32 bypass);

// AFTER (correct — rf-engine PLAYBACK_ENGINE, always initialized):
_insertSetBypass = _lib.lookupFunction<...>('track_insert_set_bypass');
typedef InsertSetBypassNative = Int32 Function(Uint32 trackId, Uint32 slot, Int32 bypass);
```

**Direct FFI Bypass Path (All Panels):**
All FabFilter panels now override `processorSlotIndex` and use direct FFI bypass via `FabFilterPanelMixin.onBypassChanged()`:
```
Panel.toggleBypass() → onBypassChanged(bypassed)
  → insertSetBypass(trackId, slotIndex, bypass) [Direct FFI to PLAYBACK_ENGINE]
  → setNodeBypassUiOnly(trackId, nodeType, bypass) [UI state sync only]
```

**Visual Bypass Overlay:**
`wrapWithBypassOverlay()` mixin method dims panel + shows "BYPASSED" label when active.

**FIXED (2026-02-16):** 4 remaining rf-bridge FFI functions migrated to rf-engine PLAYBACK_ENGINE:
- `track_insert_set_mix`, `track_insert_get_mix`, `track_insert_bypass_all`, `track_insert_get_total_latency`
- New functions created in `rf-engine/ffi.rs`, Dart FFI rebound from `ffi_insert_*` → `track_insert_*`

**Converted Panels (9 total):**
| Panel | Wrapper | Params | Status |
|-------|---------|--------|--------|
| FabFilterEqPanel | ProEqWrapper | 66 (8 bands × 8 + 2 global) | ✅ Done |
| FabFilterCompressorPanel | CompressorWrapper | 15 | ✅ Done |
| FabFilterLimiterPanel | LimiterWrapper | 6 | ✅ Done |
| FabFilterGatePanel | GateWrapper | 13 | ✅ Done |
| FabFilterReverbPanel | ReverbWrapper | 11 | ✅ Done |
| FabFilterDeEsserPanel | DeEsserWrapper | 9 | ✅ Done |
| FabFilterSaturationPanel | MultibandSaturatorWrapper | 65 (11 global + 6×9 per-band) | ✅ Done |
| FabFilterDelayPanel | DelayWrapper | 14 | ✅ Done |
| DynamicsPanel | CompressorWrapper | 15 | ✅ Done |

**Note (2026-02-17):** UltraEqWrapper also uses ProEq internally (18 params/band + 5 global). ProEq is the unified superset EQ — see "ProEq ← UltraEq Integration" in MASTER_TODO.

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
// Effects: "reverb", "algorithmic-reverb", "delay"
// Saturation: "saturation", "multiband-saturator"
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
- ✅ Cubase-style Edit Tools (10 tools: Smart, Select, Range, Split, Glue, Erase, Zoom, Mute, Draw, Play)
- ✅ Cubase-style Edit Modes (4 modes: Shuffle, Slip, Spot, Grid)
- ✅ Stereo Waveform Display (Logic Pro style L/R split with labels, threshold > 60px)
- ✅ Per-Clip Gain Drag (Listener pattern, double-tap reset to 0dB, 0.0–4.0 range)

### Cubase-Style Timeline Edit Tools + Edit Modes (2026-02-21) ✅

10 edit tools + 4 edit modes implemented from scratch with full E2E wiring.

**Provider:** `SmartToolProvider` — single instance via `ChangeNotifierProvider` in `main.dart`

**Key Files:**

| File | LOC | Description |
|------|-----|-------------|
| `providers/smart_tool_provider.dart` | ~400 | State management, enums, static helpers |
| `widgets/timeline/timeline_edit_toolbar.dart` | ~380 | Toolbar UI (10 tool buttons + 4 mode buttons + snap) |
| `widgets/timeline/clip_widget.dart` | +120 | `Consumer<SmartToolProvider>` — per-tool/mode dispatch |
| `widgets/timeline/track_lane.dart` | +15 | `onClipShuffleMove` callback |
| `widgets/timeline/timeline.dart` | +15 | `onClipShuffleMove` callback |
| `screens/engine_connected_layout.dart` | +50 | Shuffle push algorithm |

**Tools (TimelineEditTool):** Smart(1), Select(2), Range(3), Split(4), Glue(5), Erase(6), Zoom(7), Mute(8), Draw(9), Play(0)

**Modes (TimelineEditMode):**
- **Shuffle** — push adjacent clips to maintain sequence order
- **Slip** — adjust audio content within clip boundaries (sourceOffset)
- **Spot** — snap to absolute timecode positions (0.1s grid)
- **Grid** — force snap to grid regardless of snap toggle

**Critical Pattern:** Single `SmartToolProvider` instance — toolbar and `Consumer<SmartToolProvider>` in ClipWidget MUST read from same instance (via `ChangeNotifierProvider` in `main.dart`). Never create a local instance.

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

**Stereo Waveform Display (2026-02-21) ✅ — Logic Pro Style:**

Kada je track height ≥ 60px, prikazuje se stereo L/R split sa labelama i separatorom.

| Komponenta | Opis |
|------------|------|
| `_StereoWaveformPainter` | CustomPainter sa L na 25%, R na 75% vertikalne pozicije |
| Threshold | `widget.trackHeight > 60` (bilo `> 80`, default 80px = nikad prikazano) |
| L/R labele | Pre-alocirani TextPainter-i (JetBrains Mono, 8px), sa background rect-om |
| Separator | Dashed linija (6px dash, 3px gap), alpha 0.3 |
| Height guard | Labele se renderuju samo kada `size.height > 50` |
| Pipeline | `queryWaveformPixelsStereo()` → `StereoWaveformPixelData` → `_cachedStereoData` → painter |

**Gain Drag on Clips (2026-02-21) ✅:**

Per-clip gain kontrola na timeline-u sa Listener pattern-om (zaobilazi gesture arena).

| Feature | Implementacija |
|---------|----------------|
| Drag handle | `Listener.onPointerDown/Move/Up` (raw pointer events, ne kompetira sa parent-om) |
| Double-tap reset | `GestureDetector.onDoubleTap` → gain = 1.0 (0dB) |
| Range | 0.0–4.0 (−∞ to +12dB) |
| Display | `gainToDb()` helper, orange linija + dB label |
| File | `clip_widget.dart` |

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
- ✅ Third-party plugin scan/load/editor (FabFilter VST3/AU verified)
- ✅ Take lanes / Comping (recording lanes, takes, comp regions)
- ✅ Tempo track / Time warp (tempo map, time signatures, grid)

### Third-Party Plugin System (2026-02-22) ✅

Real plugin hosting via `rack` crate (v0.4) for VST3/AU loading and processing.

**Architecture:**
```
Dart: PluginProvider.scanPlugins()
  → NativeFFI.pluginScanAll()
    → Rust: plugin_scan_all()
      → PLUGIN_SCANNER.scan_all()     (for listing)
      → PLUGIN_HOST.scan_plugins()    (for loading — CRITICAL: must be synced)
        → PluginScanner scans /Library/Audio/Plug-Ins/VST3/, Components/, etc.

Dart: PluginProvider.loadPlugin(pluginId, trackId, slotIndex)
  → NativeFFI.pluginLoad(pluginId)
    → Rust: plugin_load()
      → PLUGIN_HOST.load_plugin(pluginId)
        → Vst3Host::load_with_rack() or AudioUnitHost::load_from_path()

Dart: PluginProvider.openEditor(instanceId)
  → NativeFFI.pluginOpenEditor(instanceId, 0)
    → Rust: plugin_open_editor(instanceId, null_parent)
      → instance.open_editor(null)
        → AU: rack::au::AudioUnitGui::show_window() (standalone NSWindow)
        → VST3: Not supported by rack 0.4 (generic parameter editor fallback)
```

**GUI Support by Format (macOS):**

| Format | Native GUI | Mechanism |
|--------|-----------|-----------|
| AU (`.component`) | ✅ Yes | `rack::au::AudioUnitGui::show_window()` — standalone NSWindow |
| VST3 (`.vst3`) | ❌ No | `rack 0.4` limitation — Dart shows generic parameter slider grid |
| CLAP (`.clap`) | ❌ No | Not yet implemented |

**Key Files:**

| File | Description |
|------|-------------|
| `crates/rf-plugin/src/lib.rs` | PluginHost, PluginScanner, PluginInstance trait |
| `crates/rf-plugin/src/scanner.rs` | Directory scanning, PluginInfo creation |
| `crates/rf-plugin/src/vst3.rs` | VST3/AU host via rack crate (~1046 LOC) |
| `crates/rf-engine/src/ffi.rs` | `plugin_scan_all()`, `plugin_load()`, `plugin_open_editor()` FFI |
| `flutter_ui/lib/providers/plugin_provider.dart` | Dart state management, scan/load/editor |
| `flutter_ui/lib/widgets/plugin/plugin_slot.dart` | Insert slot UI with editor open |
| `flutter_ui/lib/widgets/plugin/plugin_editor_window.dart` | Floating editor window |

**Critical Implementation Notes:**
- `PLUGIN_SCANNER` and `PLUGIN_HOST` are **separate globals** in `ffi.rs` — BOTH must be populated during scan
- `parent_window` can be NULL on macOS — AU plugins use standalone NSWindow
- External plugins in mixer go through `PluginProvider.loadPlugin()` → `PluginProvider.openEditor()`, NOT through stub `insertOpenEditor()`
- Error feedback via SnackBar on all editor open failure paths

### Grid/Snap Alignment Fix — Floating-Point Drift (2026-02-22) ✅

Grid lines and snap positions previously diverged over long timelines due to floating-point accumulation.

**Fix:** Shared `gridIntervalSeconds(snapValue, tempo)` function + integer-index iteration (`i * interval` instead of `t += interval`). `snapToGrid()` rewritten: `round(time / interval) * interval`.

**Files:**
| File | Change |
|------|--------|
| `timeline_models.dart` | `gridIntervalSeconds()`, `snapToGrid()` rewrite |
| `grid_lines.dart` | Integer-index loops, shared function, `interval <= 0` guards |
| `drag_smoothing.dart` | Use shared `gridIntervalSeconds()` |

### Waveform Gain Rendering Fix (2026-02-22) ✅

Gain adjustment used `Transform.scale(scaleY: gain)` which scaled borders/labels too. Now gain is applied directly in `_rebuildPaths()` inside CustomPainters with `_cachedGain` invalidation.

**File:** `flutter_ui/lib/widgets/timeline/clip_widget.dart` (+40/-50 LOC)

### Live Clip Drag Position in Channel Tab (2026-02-22) ✅

New `onDragLivePosition` callback piped through ClipWidget → TrackLane → Timeline → EngineConnectedLayout. During drag, Channel Tab shows the dragged position via `_dragPreviewStartTime` + `clip.copyWith(startTime:)`.

**Files:** `clip_widget.dart`, `track_lane.dart`, `timeline.dart`, `engine_connected_layout.dart`

### Auto-Crossfade at Split Points (2026-02-22) ✅

When a clip is split, a small crossfade (10-50ms, equal power) is automatically created at the split boundary to prevent clicks/pops. Method `_createCrossfadeAtSplitPoint()` in `engine_connected_layout.dart`.

### Project Tree Visual Overhaul — DAW-Style (2026-02-22) ✅

Complete visual upgrade: Material icons per type (14 types), hover effects, expand/collapse animation (150ms easeOutCubic + SizeTransition), Cubase-style depth lines, depth-based shading, type-specific accent colors.

**File:** `flutter_ui/lib/widgets/layout/project_tree.dart` (+248/-141 LOC)

### Transport Stop/Rewind — Loop Position Fix (2026-02-22) ✅

Stop/Rewind returned to loop start instead of position 0. Fixed: `_goToStart()` always → 0.0, Period/Comma shortcuts wired, Home key assigned.

**Files:** `slot_lab_screen.dart`, `engine_connected_layout.dart`, `main.dart`

### Meter Ballistic Decay — Dart-Side (2026-02-22) ✅

Professional Dart-side ballistic decay: instant rise, exponential fall (`kMeterDecay = 0.65`), noise floor gate at -80dB, smooth polling with zero-value snapshots.

**File:** `flutter_ui/lib/providers/meter_provider.dart` (+86/-30 LOC)

### Channel Tab — Source Offset Display (2026-02-22) ✅

Non-zero source offset (trimmed clip start) now shown in Channel Tab inspector.

**File:** `flutter_ui/lib/widgets/layout/channel_inspector_panel.dart` (+2 LOC)

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

**Buduće rešenje:**
- Preći na Command Pattern sa serijalizabilnim podacima
- Svaka akcija bi imala `toJson()` / `fromJson()`
- Disk offload starijih akcija preko LRU strategije

**Note:** P4 is NOW COMPLETE (2026-01-30). This task was skipped during P4 implementation due to high complexity — VoidCallback serialization requires full architectural refactor.

### P2 Status Summary (2026-01-29) ✅ ALL COMPLETE

**Completed: 26/26 (100%)**

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

**SlotLab UX Polish (2026-01-29, verified 2026-01-30):**

| Task | Status | Note |
|------|--------|------|
| P2.5-SL | ✅ | Waveform Thumbnails (80x24px, LRU cache 500, ~435 LOC) |
| P2.6-SL | ✅ | Multi-Select Layers (Ctrl/Shift+click, bulk ops) |
| P2.7-SL | ✅ | Copy/Paste Layers (clipboard, new IDs, preserve props) |
| P2.8-SL | ✅ | Fade Controls (0-1000ms, visual curves, CrossfadeCurve enum) |

**Verification:** `.claude/tasks/SLOTLAB_P2_UX_VERIFICATION_2026_01_30.md`

**Skipped: 1** (not blocking)
- P2.16 — VoidCallback not serializable, needs full refactor (skipped — low priority)

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

#### P0.4: Independent Floating Processor Editor Windows ✅ (Updated 2026-02-21)
- Rewritten [internal_processor_editor_window.dart](flutter_ui/lib/widgets/dsp/internal_processor_editor_window.dart) (~670 LOC)
- **Full FabFilter panels** embedded in floating OverlayEntry windows (9 premium panel types)
- **Authentic vintage hardware panels** for 3 vintage EQ types (Pultec, API550, Neve1073) — hardware-style knobs, CustomPainter per brand
- **Generic slider fallback** for 1 type (Expander)
- **ProcessorEditorRegistry** singleton — tracks open windows, prevents duplicates, staggered positioning
- Draggable title bar, collapse toggle, bypass button, close button

**3 Entry Points:**
| Entry Point | Gesture | File |
|-------------|---------|------|
| Mixer insert slot click | Single click | `engine_connected_layout.dart:4656` |
| FX Chain processor card | Double-tap | `fx_chain_panel.dart:198` |
| Signal Analyzer node | Single click | `signal_analyzer_widget.dart:397` |

**FabFilter Panels (9 types):** EQ (700×520), Compressor (660×500), Limiter/Gate/Reverb/Delay (620×480), Saturation (600×460), DeEsser (560×440)
**Vintage Hardware Panels (3 types):** Pultec (680×520), API550 (540×500), Neve1073 (640×520) — authentic rotary knobs
**Generic Sliders (1 type):** Expander (400×350)

**Usage:**
```dart
InternalProcessorEditorWindow.show(
  context: context,
  trackId: 0,
  slotIndex: 0,
  node: dspNode,
  position: Offset(200, 100),  // optional
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
int getBusEngineId(String busId);        // Public wrapper for _getBusEngineId()
void removeAuxSendAt(String channelId, int sendIndex);  // Remove send + FFI sync
void setChannelInserts(String id, List<InsertSlot> inserts);  // Update inserts on any channel type
```

**Modified Widgets:**
- `channel_inspector_panel.dart` — I/Ø buttons, pan right callback
- `left_zone.dart` — Monitor/PhaseInvert/PanRight callbacks
- `glass_left_zone.dart` — Glass theme variant sa istim callbacks

**FFI Integration:**
- `trackSetInputMonitor(trackIndex, bool)` — Input monitor state
- `channelStripSetInputGain(trackIndex, dB)` — Input gain trim

### SSL Channel Strip — Inspector Panel Ordering (2026-02-21) 📋 PLANNED

Channel Inspector Panel reorganizacija po SSL kanonskom signal flow redosledu (SSL 4000E/G, 9000J, Duality analiza).

**SSL Signal Flow (kanonski):**
```
Input → Filters → Dynamics → EQ → Insert → VCA Fader → Pan → Sends → Routing → Output
```

**Novi redosled sekcija (10):**

| # | Sekcija | Builder Metoda | Izvor |
|---|---------|----------------|-------|
| 1 | Channel Header | `_buildChannelHeader()` | Bez promena |
| 2 | Input | `_buildInputSection()` | NOVO (iz Routing + Controls) |
| 3 | Inserts (Pre-Fader) | `_buildPreFaderInserts()` | SPLIT iz `_buildInsertsSection()` |
| 4 | Fader + Pan | `_buildFaderPanSection()` | POMEREN DOLE iz pozicije 2 |
| 5 | Inserts (Post-Fader) | `_buildPostFaderInserts()` | SPLIT iz `_buildInsertsSection()` |
| 6 | Sends | `_buildSendsSection()` | Bez promena |
| 7 | Output Routing | `_buildOutputRoutingSection()` | SPLIT (samo Output) |
| 8-10 | Clip sections | Bez promena | Bez promena |

**Specifikacija:** `.claude/architecture/SSL_CHANNEL_STRIP_ORDERING.md`
**Fajl:** `flutter_ui/lib/widgets/layout/channel_inspector_panel.dart` (~2256 LOC)

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
| `spin` | SPIN_START, SPIN_END, REEL_SPIN_LOOP |
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

**P5 Win Tier Integration (2026-01-31):**
```dart
// Register all P5 win tier stages
void registerWinTierStages(SlotWinConfiguration config);

// Check if stage is from P5 system
bool isWinTierGenerated(String stage);

// Get all P5 stage names
Set<String> get allWinTierStageNames;
```

**P5 Registered Stages:**
| Stage Category | Priority | Pooled | Description |
|----------------|----------|--------|-------------|
| WIN_LOW..WIN_6 | 45-80 | ❌ | Regular win tiers |
| WIN_PRESENT_* | 50-85 | ❌ | Win presentation |
| ROLLUP_TICK_* | 40 | ✅ | Rapid-fire rollup |
| BIG_WIN_INTRO | 85 | ❌ | Big win start |
| BIG_WIN_TIER_1..5 | 82-90 | ❌ | Big win tiers |
| BIG_WIN_ROLLUP_TICK | 60 | ✅ | Big win rollup |

**Initialization:** `main.dart` — `StageConfigurationService.instance.init();`
**P5 Auto-Sync:** `SlotLabProjectProvider()` constructor calls `_syncWinTierStages()`

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

### P3-12 — Template Gallery System ✅ 2026-01-31

JSON-based starter templates for rapid SlotLab project setup.

**Documentation:** `.claude/architecture/TEMPLATE_GALLERY_SYSTEM.md`

**Core Features:**
- Templates are **pure JSON** (no audio files)
- Use **generic symbol IDs** (HP1, HP2, MP1, LP1, WILD, SCATTER, BONUS)
- **RTPC win system** with configurable tier thresholds
- Auto-wiring: stages, events, buses, ducking, ALE, RTPC

**Files Structure:**
```
flutter_ui/
├── lib/
│   ├── models/template_models.dart          (~650 LOC)
│   ├── services/template/                   (~1,780 LOC)
│   │   ├── template_builder_service.dart
│   │   ├── template_validation_service.dart
│   │   ├── stage_auto_registrar.dart
│   │   ├── event_auto_registrar.dart
│   │   ├── bus_auto_configurator.dart
│   │   ├── ducking_auto_configurator.dart
│   │   ├── ale_auto_configurator.dart
│   │   └── rtpc_auto_configurator.dart
│   └── widgets/template/
│       └── template_gallery_panel.dart      (~780 LOC)
└── assets/templates/                        (8 JSON files)
```

**Built-in Templates (8):**

| Template | Category | Grid | Key Features |
|----------|----------|------|--------------|
| `classic_5x3` | classic | 5×3 | 10 paylines, Free Spins |
| `ways_243` | video | 5×3 | 243 ways, multiplier wilds |
| `megaways_117649` | megaways | 6×7* | Cascade, Free Spins |
| `cluster_pays` | cluster | 7×7 | Cluster wins, Cascade |
| `hold_and_win` | holdWin | 5×3 | Coins, Respins, 4-tier jackpots |
| `cascading_reels` | video | 5×4 | Tumble, escalating multipliers |
| `jackpot_network` | jackpot | 5×3 | Progressive jackpots, wheel |
| `bonus_buy` | video | 5×4 | Feature buy, multiplier wilds |

**TemplateCategory Enum:**
```dart
enum TemplateCategory {
  classic,    // Classic payline slots
  video,      // Modern video slots
  megaways,   // Dynamic reel slots
  cluster,    // Cluster pays
  holdWin,    // Hold & Win / Lightning Link
  jackpot,    // Progressive jackpot
  branded,    // Licensed/themed
  custom,     // User-created
}
```

**Win Tiers (Configurable):**
```dart
class WinTierConfig {
  final WinTier tier;           // tier1-tier6
  final String label;           // "Win", "Big Win", "Mega Win"
  final double threshold;       // x bet (1.0, 5.0, 15.0, 30.0, 60.0, 100.0)
  final double volumeMultiplier;
  final double pitchOffset;
  final int rollupDurationMs;
  final bool hasScreenEffect;
}
```

**Usage Flow:**
1. Select template from gallery
2. `TemplateBuilderService.buildTemplate()` auto-wires all systems
3. User assigns audio files to placeholder events
4. Test in SlotLab → Export

**UI Integration (P3-15, 2026-01-31):**
- 📦 Templates button u SlotLab header (levo od status chips)
- Blue gradient button sa tooltip
- Otvara modal dialog sa TemplateGalleryPanel
- "Apply" primenjuje template na projekat (reelCount, rowCount)

---

### P3-16 — Coverage Indicator ✅ 2026-01-31

Audio assignment progress tracking u SlotLab header-u.

**Implementacija:**
- Kompaktni badge: `X/341` sa mini progress bar-om
- Boje: Red (<25%), Orange (25-75%), Green (>75%)
- Klik otvara breakdown popup po sekcijama
- Consumer<SlotLabProjectProvider> za reaktivno ažuriranje

**Files:**
- `flutter_ui/lib/screens/slot_lab_screen.dart`:
  - `_buildCoverageBadge()` (~80 LOC)
  - `_showCoverageBreakdown()` — popup dialog
  - `_buildCoverageRow()` — helper za breakdown

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

**Win Skip Fixes (2026-02-14) ✅:**
- **P1.6: Win Line Guard** — Stale `.then()` callbacks on `_winAmountController.reverse()` from original win flow blocked via `_winTier.isEmpty` checks at 3 guard points
- **P1.7: Skip END Stages** — `_executeSkipFadeOut()` now stops all win audio + triggers END stages (`ROLLUP_END`, `BIG_WIN_END`, `WIN_PRESENT_END`, `WIN_COLLECT`), matching fullscreen mode parity
- **Files:** `slot_preview_widget.dart` — `_executeSkipFadeOut()`, `_startWinLinePresentation()`, rollup callbacks

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
- **Audio Preview (V6.2, V6.4)** — Manual play/stop buttons, waveform visualization (hover auto-play disabled)

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

### SlotLab V6.6 — Multi-Select Drag-Drop (2026-01-26) ✅ COMPLETE

Multiple audio file drag-drop support across all SlotLab audio browsers.

**Podržani Data Tipovi:**
| Data Type | Izvor |
|-----------|-------|
| `AudioAsset` | AudioAssetManager pool |
| `String` | Single file path |
| `List<String>` | **Multi-select** (novo) |
| `AudioFileInfo` | Audio browser metadata |

**Multi-Select UI:**
- **Long-press** na audio chip → toggle selekcija
- **Checkbox** prikazan na svakom chipu (levo)
- **Zelena boja** za selektovane iteme
- Drag selektovanih → prenosi `List<String>`
- Feedback: "X files" za više od 1 fajla
- Auto-clear selekcije na drag end

**Ažurirani Callback Signatures:**
| Komponenta | Callback | Tip |
|------------|----------|-----|
| `AudioBrowserDock` | `onAudioDragStarted` | `Function(List<String>)?` |
| `EventsPanelWidget` | `onAudioDragStarted` | `Function(List<String>)?` |
| `SlotLabScreen` | `_draggingAudioPaths` | `List<String>?` |

**DropTargetWrapper:**
```dart
// Accepts List<String> for multi-select
if (details.data is List<String>) {
  final paths = details.data as List<String>;
  for (final path in paths) {
    assets.add(_pathToAudioAsset(path));
  }
}
// Process all dropped assets
for (final asset in assets) {
  _handleDrop(asset, details.offset, provider);
}
```

**Fajlovi:**
| File | Changes |
|------|---------|
| `audio_browser_dock.dart` | `_selectedPaths` Set, checkbox UI, `Draggable<List<String>>` |
| `events_panel_widget.dart` | Callback signature `List<String>` |
| `drop_target_wrapper.dart` | Accept & process `List<String>` |
| `slot_lab_screen.dart` | `_draggingAudioPaths: List<String>?`, overlay "X files" |

**Dokumentacija:** `.claude/architecture/SLOTLAB_DROP_ZONE_SPEC.md` (Section 2.3)

### SlotLab V6.5 — Bottom Audio Browser Dock (2026-01-26) ✅ COMPLETE

Industry-standard horizontal audio browser dock (Wwise/FMOD pattern).

**New Widget:** `audio_browser_dock.dart` (~640 LOC)

**Layout Change:**
```
┌────────────┬────────────────────────────────┬─────────────────────┐
│  ULTIMATE  │                                │    EVENTS           │
│  AUDIO     │         SLOT MACHINE           │    PANEL            │
│  PANEL     │         (CENTER)               │   (Inspector)       │
├────────────┴────────────────────────────────┴─────────────────────┤
│  AUDIO BROWSER DOCK (horizontal, 90px height, collapsible)        │
├───────────────────────────────────────────────────────────────────┤
│  LOWER ZONE (existing bottom panel)                               │
└───────────────────────────────────────────────────────────────────┘
```

**Features:**
| Feature | Description |
|---------|-------------|
| **Horizontal scroll** | Audio files displayed as compact chips |
| **Pool/Files toggle** | Switch between AudioAssetManager pool and file system |
| **Multi-select drag** | Long-press to select, drag multiple files at once |
| **Drag-drop** | Drag audio chips to any drop target |
| **Play/Stop** | Click chip to preview, click again to stop |
| **Search** | Filter files by name |
| **Import** | Import files or folder buttons |
| **Collapsible** | Click header to collapse (28px) or expand (90px) |
| **Format badges** | Color-coded extension badges (WAV=blue, MP3=orange, etc.) |

**Integration:**
- `slot_lab_screen.dart` — Added `AudioBrowserDock` above bottom panel
- `_audioBrowserDockExpanded` state variable for collapse toggle
- `onAudioDragStarted` callback for drag overlay (supports `List<String>`)

### SlotLab V6.4 — Audio Preview Improvements (2026-01-26) ✅ COMPLETE

**Audio Preview (EventsPanelWidget):**
- ~~500ms hover delay before playback starts~~ **DISABLED**
- Manual Play/Stop button (visible on hover or while playing)
- Waveform visualization during preview
- Green accent when playing, blue when idle
- Playback continues until manually stopped

### SlotLab V6.3 — UX Improvements (2026-01-25) ✅ COMPLETE

Quality-of-life improvements for audio authoring workflow.

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
| `slot_lab_screen.dart` | Reset callback wiring + Audio Browser Dock |
| `audio_browser_dock.dart` | **NEW** — Bottom dock widget (~520 LOC) |

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
- `DropTargetWrapper` koristi ovaj servis za generisanje eventId direktno
- Events Panel prikazuje 3-kolonski format: NAME | STAGE | LAYERS

**Event Name Editing (2026-01-24):**

| Lokacija | Trigger | Behavior |
|----------|---------|----------|
| Events Panel | Double-tap | Inline edit mode, orange border |

**Note (2026-01-30):** QuickSheet je uklonjen. Event kreacija sada ide direktno kroz DropTargetWrapper → MiddlewareProvider.

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

### SlotLab Drop Zone System (2026-01-23, Updated 2026-01-30) ✅

Drag-drop audio na mockup elemente → automatsko kreiranje eventa.

**Arhitektura (Updated 2026-01-30):**
```
Audio File (Browser) → Drop on Mockup Element → DropTargetWrapper
                                                     ↓
                                          SlotCompositeEvent (direktno)
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

**Implementation (2026-01-30):**
- `DropTargetWrapper` kreira `SlotCompositeEvent` direktno putem `MiddlewareProvider`
- QuickSheet popup uklonjen — streamlined flow
- Callback `_onEventBuilderEventCreated()` samo prikazuje feedback SnackBar

**Edit Mode UI (V6.1):**
- Enhanced mode toggle button sa glow efektom (active) i clear labels
- "DROP ZONE ACTIVE" banner iznad slot grida kada je edit mode aktivan
- EXIT button za brzi izlaz iz edit mode-a
- Visual hierarchy: Banner → Slot Grid → Controls

**Dokumentacija:**
- `.claude/architecture/SLOTLAB_DROP_ZONE_SPEC.md`
- `.claude/docs/AUTOEVENTBUILDER_REMOVAL_2026_01_30.md`

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

**Auto-detekcija stage-ova:**
- `REEL_SPIN_LOOP` → Jedan looping audio za sve reel-ove
- `REEL_STOP_0..4` → Per-reel stop sa stereo pan, fade-out spin loop
- `SPIN_END` → Fallback: zaustavlja spin loop ako je još aktivan

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

### Advanced Audio Features (2026-01-25) ✅

**Reel Spin Audio System (Updated 2026-01-31)**

| Stage | Svrha |
|-------|-------|
| `REEL_SPIN_LOOP` | Jedan looping audio za sve reel-ove tokom spina |
| `REEL_STOP_0..4` | Per-reel stop zvuk sa automatskim stereo pan-om |

**Note:** Per-reel spinning (`REEL_SPINNING_0..4`) je uklonjen — koristi se jedan `REEL_SPIN_LOOP`.
Stereo pozicioniranje se postiže kroz `REEL_STOP_0..4` sa pan vrednostima (-0.8 do +0.8).

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
   - VS Code-style shortcuts: **Cmd+K** (Mac) / **Ctrl+K** (Windows/Linux)
   - Fuzzy search with scoring
   - Keyboard navigation (↑/↓, Enter, Escape)
   - 16 pre-built FluxForge DAW commands with shortcuts
   - FluxForgeCommands class for extensibility

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
SPIN_START, SPIN_END, REEL_SPIN_LOOP, REEL_STOP, REEL_STOP_0..4

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

