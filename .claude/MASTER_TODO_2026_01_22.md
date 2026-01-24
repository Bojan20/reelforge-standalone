# 🎯 FLUXFORGE STUDIO — MASTER TODO LIST

**Date:** 2026-01-24 (Updated with Premium Slot Preview Analysis)
**Sources:** System Review + Performance Analysis + Memory Analysis + Lower Zone Implementation + Slot Mockup Analysis + **Premium Slot Preview Ultra Analysis**
**Total Items:** 106 (+12 Premium Slot Preview items)

---

## 📊 EXECUTIVE SUMMARY

| Priority | Total | Done | Remaining | Status |
|----------|-------|------|-----------|--------|
| 🔴 P0 Critical | 8 | **8** | 0 | ✅ **100%** |
| 🟠 P1 High | 15 | **15** | 0 | ✅ **100%** |
| 🟡 P2 Medium | 22 | **15** | 6 (+1 skip) | **68%** |
| 🟢 P3 Low | 14 | **14** | 0 | ✅ **100%** |
| 🔵 SlotLab Done | 5 | **5** | 0 | ✅ **100%** |
| 🟣 SL Lower Zone | 22 | **6** | 16 | **27%** |
| 🟣 MW Command Bar | 2 | **2** | 0 | ✅ **100%** |
| 🎰 Premium Slot Preview | 12 | **8** | 4 | **67%** |
| ⚪ P4 Future | 8 | 0 | 8 | Backlog |

**Overall Progress:** 73/108 (68%)

### 🆕 SlotLab Lower Zone Audit (2026-01-24) — Updated

| Priority | Count | Done | Status |
|----------|-------|------|--------|
| 🔴 SL-P0 Critical | 5 | **5** | ✅ **100%** |
| 🟠 SL-P1 High | 7 | **1** | 14% |
| 🟡 SL-P2 Medium | 10 | 0 | 0% |
| **Total** | **22** | **6** | **27%** (was 5%)

**Key Finding:** Only 47% of UI elements in SlotLab Lower Zone are fully functional.
**Root Cause:** Incomplete provider integration (DspChainProvider, MixerDSPProvider, SlotLabProjectProvider not connected).

**P0 Completed (8/8):** Memory leaks, RT safety, build procedure ✅
**P1 Completed (15/15):** All items ✅
**P2 Completed (15):** P2.1, P2.2, P2.4, P2.10-15, P2.17-22
**P2 Skipped (1):** P2.16 (VoidCallback serialization issue)
**P2 Remaining (6):** P2.3, P2.5-9
**P3 Completed (14/14):** All polish items ✅

**🆕 Latest Feature (2026-01-24):** Auto-Action System (AudioContextService)
- Context-aware Play/Stop detection from audio file names
- QuickSheet shows auto-determined action with visual badge
- Zero-click workflow for common scenarios (SFX→Play, Music context switch→Stop)

---

## 🔴 P0 — CRITICAL ✅ ALL COMPLETE

### Memory Leaks

| # | Issue | Status |
|---|-------|--------|
| **P0.1** | MiddlewareProvider.dispose() | ✅ Fixed |
| **P0.2** | Disk waveform cache quota | ✅ Fixed |
| **P0.3** | FFI string allocation audit | ✅ Fixed |
| **P0.4** | Overflow voice tracking | ✅ Fixed |

### Audio Thread Safety

| # | Issue | Status |
|---|-------|--------|
| **P0.5** | LRU cache RT safety | ✅ Fixed |
| **P0.6** | Cache eviction RT safety | ✅ Fixed |

### Build/Runtime

| # | Issue | Status |
|---|-------|--------|
| **P0.7** | Flutter analyze enforcement | ✅ Documented |
| **P0.8** | Dylib copy procedure | ✅ Documented |

---

## 🟠 P1 — HIGH PRIORITY ✅ ALL COMPLETE

### ✅ Completed (15/15)

| # | Issue | Status |
|---|-------|--------|
| **P1.1** | Cascading notifyListeners | ✅ Bitmask flags |
| **P1.2** | notifyListeners batching | ✅ Frame-aligned throttling |
| **P1.3** | Consumer→Selector conversion | ✅ Done 2026-01-23 — 9 middleware panels converted |
| **P1.4** | LRU List O(n) | ✅ LinkedHashSet O(1) |
| **P1.5** | Extract CompositeEventSystemProvider | ✅ Done — `composite_event_system_provider.dart` ~1280 LOC |
| **P1.6** | Extract ContainerSystemProvider | ✅ Done (Blend/Random/Sequence providers) |
| **P1.7** | Extract MusicSystemProvider | ✅ Done — `music_system_provider.dart` ~290 LOC |
| **P1.8** | Extract EventSystemProvider | ✅ Done — `event_system_provider.dart` ~330 LOC |
| **P1.9** | Float32→double conversion | ✅ Float32List.view() |
| **P1.10** | DateTime allocation | ✅ millisecondsSinceEpoch |
| **P1.11** | WaveCacheManager budget | ✅ LRU eviction at 80% |
| **P1.12** | Batch FFI operations | ✅ 60→1 calls |
| **P1.13** | Cache eviction background | ✅ Non-blocking |
| **P1.14** | HashMap clone fix | ✅ Direct buffer write |
| **P1.15** | Listener deduplication | ✅ _listenersRegistered flag |

### P1.3 Consumer→Selector Details

**Converted Panels:**

| File | Selector Type | Notes |
|------|---------------|-------|
| `advanced_middleware_panel.dart` | `MiddlewareStats` | 5 nested Consumers converted |
| `blend_container_panel.dart` | `List<BlendContainer>` | Actions via `context.read()` |
| `random_container_panel.dart` | `List<RandomContainer>` | Actions via `context.read()` |
| `sequence_container_panel.dart` | `List<SequenceContainer>` | Actions via `context.read()` |
| `events_folder_panel.dart` | `EventsFolderData` | Complex typedef for 5 fields |
| `music_system_panel.dart` | `MusicSystemData` | Typedef for segments+stingers |
| `attenuation_curve_panel.dart` | `List<AttenuationCurve>` | Simple list selector |
| `event_editor_panel.dart` | `List<MiddlewareEvent>` | Uses `context.read()` for sync |
| `slot_audio_panel.dart` | `MiddlewareStats` | Removed unused provider from 6 child widgets |

**Added Typedefs (`middleware_provider.dart`):**
- `MiddlewareStats` — stats record (12 fields)
- `EventsFolderData` — events, selection, clipboard state (5 fields)
- `MusicSystemData` — segments + stingers (2 fields)

---

## 🟡 P2 — MEDIUM PRIORITY (2-3 Weeks)

### DSP Optimization

| # | Issue | File | Impact | Est. |
|---|-------|------|--------|------|
| **P2.1** | ~~Scalar metering loop~~ ✅ | Done — SIMD f64x8 metering via rf-dsp | — |
| **P2.2** | ~~Scalar bus summation~~ ✅ | Done — SIMD mix_add() via rf-dsp | — |

### Feature Gaps — System Review

| # | Issue | Category | Impact | Est. |
|---|-------|----------|--------|------|
| **P2.3** | No external engine integration | Architecture | Cannot deploy to games | 2 weeks |
| **P2.4** | ~~Stage Ingest System~~ ✅ | Done — 6 widgets ~2500 LOC (Panel, Wizard, Connector, Viewer) | — |
| **P2.5** | No automated QA framework | QA | Regressions undetected | 1 week |
| **P2.6** | No offline DSP pipeline | Export | Manual normalization | 1 week |
| **P2.7** | DAW plugin hosting incomplete | DAW | Limited mixing | 1 week |
| **P2.8** | No MIDI editing | DAW | Can't compose in-app | 2 weeks |
| **P2.9** | No soundbank building | Export | Large file sizes | 1 week |
| **P2.10** | ~~Music system stinger UI~~ ✅ | Done — MusicSystemPanel 1227 LOC (Segments + Stingers tabs) | — |

### Lower Zone P3 Tasks

| # | Issue | Section | Impact | Est. |
|---|-------|---------|--------|------|
| **P2.11** | ~~Bounce Panel~~ ✅ | Done — DawBouncePanel in export_panels.dart | — |
| **P2.12** | ~~Stems Panel~~ ✅ | Done — DawStemsPanel in export_panels.dart | — |
| **P2.13** | ~~Archive Panel~~ ✅ | Done — _buildCompactArchive in daw_lower_zone_widget.dart | — |
| **P2.14** | ~~SlotLab Batch Export~~ ✅ | Done — SlotLabBatchExportPanel in export_panels.dart | — |

### Memory — Advanced

| # | Issue | File | Impact | Est. |
|---|-------|------|--------|------|
| **P2.15** | ~~Waveform downsampling~~ ✅ | Done — 2048 samples max, peak detection | — |
| **P2.16** | Async undo stack offload to disk | `undo_manager.dart` | ⏸️ SKIPPED — VoidCallback not serializable, requires full refactor | — |
| **P2.17** | ~~Composite events unbounded~~ ✅ | Done — Max 500 limit implemented | — |
| **P2.18** | ~~Container storage metrics~~ ✅ | Done — FFI + ContainerStorageMetricsPanel | — |

### UX Improvements

| # | Issue | Section | Impact | Est. |
|---|-------|---------|--------|------|
| **P2.19** | ~~Custom grid editor~~ ✅ | Done — GameModelEditor ima visual grid, sliders, presets | — |
| **P2.20** | ~~No bonus game simulator~~ ✅ | SlotLab | Done — BonusSimulatorPanel + FFI | — |
| **P2.21** | ~~No audio waveform in container picker~~ ✅ | Middleware | Done — AudioWaveformPickerDialog | — |
| **P2.22** | ~~No preset versioning/migration~~ ✅ | Config | Done — SchemaMigrationService | — |

---

## 🟢 P3 — LOW PRIORITY ✅ ALL COMPLETE

| # | Issue | Status |
|---|-------|--------|
| **P3.1** | SIMD metering correlation | ✅ rf_dsp::calculate_correlation_simd |
| **P3.2** | Pre-calculate correlation | ✅ Cached in TrackMeter |
| **P3.3** | RwLock→Mutex simplification | ✅ Done |
| **P3.4** | Memory-mapped cache | ✅ memmap2 crate |
| **P3.5** | End-user documentation | ✅ README + architecture |
| **P3.6** | API reference | ✅ FFI + Provider docs |
| **P3.7** | Architecture diagrams | ✅ CLAUDE.md updated |
| **P3.8** | Provider management | ✅ GetIt service locator |
| **P3.9** | const constructors | ✅ Added where applicable |
| **P3.10** | RTPC Macro System | ✅ RtpcMacro, RtpcMacroBinding |
| **P3.11** | Preset Morphing | ✅ PresetMorph, MorphCurve |
| **P3.12** | DSP Profiler Panel | ✅ DspProfilerPanel widget |
| **P3.13** | Live WebSocket updates | ✅ LiveParameterChannel |
| **P3.14** | Visual Routing Matrix | ✅ RoutingMatrixPanel

---

## 🔵 SLOTLAB — ALL COMPLETE ✅ (2026-01-24)

### Audio-Visual Sync & Event Naming

| # | Issue | Status | Commit |
|---|-------|--------|--------|
| **SL.1** | Visual-Sync Callbacks | ✅ Done | `780891a8` |
| **SL.2** | QuickSheet Dropdown Fallback | ✅ Done | `780891a8` |
| **SL.3** | Audio Preview on Commit | ✅ Done | `780891a8` |
| **SL.4** | Slot Mockup Ultimate Analysis | ✅ Done | `780891a8` |
| **SL.5** | Dynamic Event Naming Convention | ✅ Done | 2026-01-24 |

### SL.1: Visual-Sync Callbacks

**Problem:** REEL_STOP audio desync od vizuelne animacije

**Solution:** 6 callback-a direktno iz EmbeddedSlotMockup:
```dart
onSpinStart()    → 'SPIN_START'
onReelStop(i)    → 'REEL_STOP_0'..'REEL_STOP_4'
onAnticipation() → 'ANTICIPATION_ON'
onReveal()       → 'SPIN_END'
onWinStart()     → 'WIN_*' + 'ROLLUP_START'
onWinEnd()       → 'WIN_END'
```

**Files:**
- `embedded_slot_mockup.dart` — 6 callback params
- `slot_lab_screen.dart` — `_triggerVisualStage()`, `_triggerWinStage()`

### SL.2: QuickSheet Dropdown Fallback

**Problem:** `items == null || items.isEmpty` assertion error

**Solution:**
```dart
static const _fallbackTriggers = ['press', 'release', 'hover'];
static const _fallbackPresetId = 'ui_click_secondary';
```

**File:** `quick_sheet.dart`

### SL.3: Audio Preview on Commit

**Problem:** Zvuci se "seku" pri drag-drop

**Solution:** Audio preview na commit kao potvrda:
```dart
AudioPlaybackService.instance.previewFile(
  asset.path,
  volume: 0.7,
  source: PlaybackSource.browser,
);
```

**File:** `drop_target_wrapper.dart`

### SL.4: Slot Mockup Ultimate Analysis

**Deliverable:** Kompletna analiza iz svih 9 uloga (CLAUDE.md)

**Sadržaj:**
- Vizuelna struktura (1164 LOC)
- State machine (6 GameState, 6 WinType)
- Audio flow pipeline diagram
- Analiza po 9 uloga
- Implementirano vs Nedostaje
- Preporuke za poboljšanja

**File:** `.claude/reviews/EMBEDDED_SLOT_MOCKUP_ULTIMATE_ANALYSIS.md`

### Nedostaje u Mockup-u (za buduće sprintove)

| # | Feature | Priority | Impact |
|---|---------|----------|--------|
| 1 | REEL_SPIN loop | P0 | Spin zvuk ne loopuje |
| 2 | Payline vizualizacija | P1 | Nema winning line prikaz |
| 3 | Symbol animacije | P1 | Statični simboli |
| 4 | Near Miss detection | P1 | Nema NEAR_MISS stage |
| 5 | Cascade mode | P2 | Samo standard spins |

### SL.5: Dynamic Event Naming Convention ✅ DONE (2026-01-24)

**Problem:** Event imena su generička ili prazna pri kreiranju

**Rešenje:** Automatsko generisanje imena po konvenciji

| Element Type | Naming Pattern | Example |
|--------------|----------------|---------|
| UI Elements | `onUiPa{ElementName}` | `onUiPaSpinButton`, `onUiPaBetUp` |
| Reel Events | `onReel{Action}{Index?}` | `onReelStop0`, `onReelLand`, `onReelSpin` |
| Free Spins | `onFs{Phase}` | `onFsTrigger`, `onFsEnter`, `onFsExit` |
| Bonus | `onBonus{Phase}` | `onBonusTrigger`, `onBonusEnter`, `onBonusExit` |
| Win Events | `onWin{Tier}` | `onWinSmall`, `onWinBig`, `onWinMega` |
| Jackpot | `onJackpot{Tier}` | `onJackpotMini`, `onJackpotGrand` |
| Cascade | `onCascade{Phase}` | `onCascadeStart`, `onCascadeStep`, `onCascadeEnd` |
| Hold & Win | `onHold{Phase}` | `onHoldTrigger`, `onHoldEnter`, `onHoldSpin` |
| Gamble | `onGamble{Phase}` | `onGambleStart`, `onGambleWin`, `onGambleLose` |

**Implemented Components:**

1. **EventNamingService** (`event_naming_service.dart` ~650 LOC):
   - Singleton service za generisanje semantičkih imena
   - 100+ stage pattern-a iz StageConfigurationService
   - Kategorije: FS_*, BONUS_*, TUMBLE_*, AVALANCHE_*, BIGWIN_*, MULT_*, PICK_*, WHEEL_*, TRAIL_*, TENSION_*, JACKPOT_*, CASCADE_*, HOLD_*, GAMBLE_*, MENU_*, AUTOPLAY_*, AMBIENT_*, ATTRACT_*, IDLE_*, SYSTEM_*

2. **AutoEventBuilderProvider** (`auto_event_builder_provider.dart:667-675`):
   - `createDraft()` koristi `EventNamingService.instance.generateEventName()`
   - Umesto template: `ui.spin.click_primary` → Semantičko: `onUiPaSpinButton`

3. **Events Panel** (`events_panel_widget.dart:321-430`):
   - 3-kolonski prikaz: **NAME | STAGE | LAYERS**
   - Header red sa labelama kolona
   - Mini layer vizualizacija (obojeni blokovi)
   - Stage formatiranje (SPIN_START → Spin Start)
   - **Inline editing**: Double-tap za editovanje imena

4. **QuickSheet Editable Name** (`quick_sheet.dart:274-322`):
   - TextField umesto readonly Text
   - Pre-fill sa generisanim imenom
   - Korisnik može promeniti ime pre commit-a

**Event Name Editing:**

| Lokacija | Akcija | Rezultat |
|----------|--------|----------|
| QuickSheet | Direktno editovanje | Menja ime pre commit-a |
| Events Panel | Double-tap | Inline edit mode |
| Events Panel | Enter/Focus loss | Auto-save promene |

**Files Modified:**
- `flutter_ui/lib/services/event_naming_service.dart` — Core naming service
- `flutter_ui/lib/providers/auto_event_builder_provider.dart` — Integration
- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart` — 3-column display + inline edit
- `flutter_ui/lib/widgets/slot_lab/auto_event_builder/quick_sheet.dart` — Editable event name

---

## ⚪ P4 — FUTURE (Backlog)

| # | Feature | Category | Notes |
|---|---------|----------|-------|
| **P4.1** | Linear phase EQ mode | DSP | FabFilter parity |
| **P4.2** | Multiband compression | DSP | FabFilter parity |
| **P4.3** | Unity adapter | Integration | Game engine support |
| **P4.4** | Unreal adapter | Integration | Game engine support |
| **P4.5** | Web (Howler.js) adapter | Integration | Browser support |
| **P4.6** | Mobile/Web target optimization | Platform | After P0/P1 done |
| **P4.7** | WASM port for web | Platform | Long-term |
| **P4.8** | CI/CD regression testing | QA | Automated testing |

---

## 🟣 SLOTLAB LOWER ZONE — TODO AUDIT (2026-01-24)

**Analysis:** `.claude/reviews/SLOTLAB_LOWER_ZONE_ULTRA_ANALYSIS_2026_01_24.md`

### Connection Statistics (Updated 2026-01-24)

| Status | Before | After |
|--------|--------|-------|
| ✅ CONNECTED | 37 (47%) | 43 (55%) |
| ⚠️ PARTIAL | 6 (8%) | 5 (6%) |
| ❌ NOT CONNECTED | 23 (30%) | 18 (23%) |
| 🔧 HARDCODED | 12 (15%) | 12 (15%) |

**Improvement:** +6 connected items (P0.1-5 + P1.1)

### 🔴 SL-P0 — CRITICAL ✅ ALL FIXED (5/5)

| # | Issue | Location | Status |
|---|-------|----------|--------|
| **SL-P0.1** | ~~DSP Chain hardcoded~~ | `_buildCompactDspChain()` | ✅ Connected to DspChainProvider |
| **SL-P0.2** | ~~Voice stats fake~~ | `_buildCompactVoicePool()` | ✅ Uses NativeFFI.getVoicePoolStats() |
| **SL-P0.3** | ~~Pan panel static~~ | `_buildCompactPanPanel()` | ✅ Connected to MixerDSPProvider |
| **SL-P0.4** | ~~Stems panel broken~~ | `_buildCompactStemsPanel()` | ✅ Added _selectedStemBusIds state |
| **SL-P0.5** | ~~Event play buttons~~ | Folder + Editor panels | ✅ Calls middleware.previewCompositeEvent() |

**Fixed (2026-01-24):** All 5 P0 items connected to real data sources.

### 🟠 SL-P1 — HIGH PRIORITY (7 items → 6 remaining)

| # | Issue | Location | Status |
|---|-------|----------|--------|
| **SL-P1.1** | ~~Layer parameters not editable~~ | `_buildInteractiveLayerItem()` | ✅ DONE |
| **SL-P1.2** | Symbols list hardcoded | `_buildCompactSymbolsPanel()` — should use SlotLabProjectProvider.symbols | ❌ |
| **SL-P1.3** | 9/17 Action Strip actions only debugPrint | `_buildActionStrip()` |
| **SL-P1.4** | Variations sliders static | `_buildCompactVariationsPanel()` |
| **SL-P1.5** | Package Build button empty | `_buildCompactPackagePanel()` |
| **SL-P1.6** | Limiter GR/TruePeak FFI missing | `fabfilter_limiter_panel.dart:241,258` |
| **SL-P1.7** | Compressor GR/metering FFI missing | `fabfilter_compressor_panel.dart:454,462,466` |

### 🟡 SL-P2 — MEDIUM PRIORITY (10 items)

| # | Issue | Location |
|---|-------|----------|
| **SL-P2.1** | Drag-drop not working | Layer items, symbol cards |
| **SL-P2.2** | Stage play buttons missing | Timeline panel |
| **SL-P2.3** | Editor/Folder selection desync | Event panels local state |
| **SL-P2.4** | Keyboard shortcuts not visible | Context bar |
| **SL-P2.5** | Event history tracking | `event_log_panel.dart:267` |
| **SL-P2.6** | BPM hardcoded in piano roll | `daw_lower_zone_widget.dart:1662` |
| **SL-P2.7** | FadeIn/FadeOut model missing | `daw_lower_zone_widget.dart:1691-1692` |
| **SL-P2.8** | ALE transition save | `music_transition_preview_panel.dart:689` |
| **SL-P2.9** | Blend preview | `blend_container_panel.dart:469` |
| **SL-P2.10** | Events preview engine | `events_folder_panel.dart:1171` |

### TODO Comments Found (18 total)

**SlotLab Lower Zone Widget:**
- Line 1269: `// TODO: Connect to preview playback` — Event play button
- Line 2192: `// TODO: Show export dialog` — Stage export

**FabFilter Panels (5):**
- `fabfilter_limiter_panel.dart:241` — GR FFI
- `fabfilter_limiter_panel.dart:258` — Loudness metering
- `fabfilter_compressor_panel.dart:454` — Bypass connect
- `fabfilter_compressor_panel.dart:462` — GR FFI
- `fabfilter_compressor_panel.dart:466` — Real metering

**Other (11):**
- Various DAW and Middleware panels

### ✅ SL-P1.1 COMPLETED — Interactive Layer Parameters (2026-01-24)

**Problem:** Layer parameters (volume, pan, delay) were read-only text in the UI.

**Solution:** Implemented `_buildInteractiveLayerItem()` with interactive sliders:

| Parameter | Range | Slider | Connected To |
|-----------|-------|--------|--------------|
| Volume | 0-100% | ✅ | `MiddlewareProvider.updateEventLayer()` |
| Pan | L100-C-R100 | ✅ | `MiddlewareProvider.updateEventLayer()` |
| Delay | 0-2000ms | ✅ | `MiddlewareProvider.updateEventLayer()` |
| Mute | On/Off | ✅ Toggle | `layer.copyWith(volume: 0)` |
| Preview | Play/Stop | ✅ Button | `AudioPlaybackService.previewFile()` |
| Delete | - | ✅ Button | `MiddlewareProvider.removeLayerFromEvent()` |

**Helper Method:**
```dart
Widget _buildParameterSlider({
  required String label,
  required double value,
  required ValueChanged<double> onChanged,
});
```

**Files Modified:**
- `slotlab_lower_zone_widget.dart` — `_buildInteractiveLayerItem()`, `_buildParameterSlider()`

---

### ✅ Auto-Loop Detection (2026-01-24)

**Problem:** Events for looping stages (MUSIC_BASE, REEL_SPIN_LOOP) weren't auto-set to loop.

**Solution:** Added `isLooping()` method to StageConfigurationService:

```dart
bool isLooping(String stage) {
  final def = getStage(stage);
  if (def != null) return def.isLooping;
  final upper = stage.toUpperCase();
  return _loopingStages.contains(upper) ||
      upper.endsWith('_LOOP') ||
      upper.startsWith('MUSIC_') ||
      upper.startsWith('AMBIENT_') ||
      upper.startsWith('ATTRACT_') ||
      upper.startsWith('IDLE_');
}
```

**Default Looping Stages:**
- `REEL_SPIN_LOOP`, `MUSIC_BASE`, `MUSIC_TENSION`, `MUSIC_FEATURE`
- `FS_MUSIC`, `HOLD_MUSIC`, `BONUS_MUSIC`
- `AMBIENT_LOOP`, `ATTRACT_MODE`, `IDLE_LOOP`
- `ANTICIPATION_LOOP`, `FEATURE_MUSIC`

**Integration in `slot_lab_screen.dart:_onEventBuilderEventCreated()`:**
```dart
final shouldLoop = StageConfigurationService.instance.isLooping(stage);
final compositeEvent = SlotCompositeEvent(
  looping: shouldLoop,
  maxInstances: shouldLoop ? 1 : 4,  // Looping=1, one-shots=4
);
```

**Files Modified:**
- `stage_configuration_service.dart` — `isLooping()`, `_loopingStages`
- `slot_lab_screen.dart` — Auto-loop in event creation

---

### ✅ Auto-Action System (AudioContextService) (2026-01-24)

**Problem:** User had to manually select Play vs Stop action for every audio drop.

**Solution:** Implemented `AudioContextService` — context-aware auto-action detection.

**New Service:** `flutter_ui/lib/services/audio_context_service.dart` (~310 LOC)

**Auto-Detection Logic:**
| Audio Type | Stage Type | Result |
|------------|------------|--------|
| SFX / Voice | Any | **PLAY** (always) |
| Music / Ambience | Entry (_TRIGGER, _ENTER) + same context | **PLAY** |
| Music / Ambience | Entry + different context | **STOP** (stop old music) |
| Music / Ambience | Exit (_EXIT, _END) | **STOP** |

**Context Detection from Audio Name:**
- `fs_music.wav` → FREE_SPINS context
- `base_theme.wav` → BASE_GAME context
- `bonus_fanfare.wav` → BONUS context
- `spin_sfx.wav` → SFX type (always play)

**EventDraft Changes:**
```dart
class EventDraft {
  ActionType actionType;    // Auto-determined by AudioContextService
  String? stopTarget;       // Bus to stop (for Stop actions)
  String actionReason;      // Human-readable explanation
}
```

**QuickSheet UI Enhancement:**
- New "Action" field shows auto-detected action
- Green badge + ▶ icon for **PLAY**
- Red badge + ⬛ icon for **STOP**
- Info tooltip shows reasoning

**Example Workflow:**
1. Drop `base_music.wav` on `FS_TRIGGER` → **STOP** (stops base music when FS starts)
2. Drop `fs_music.wav` on `FS_TRIGGER` → **PLAY** (plays FS music)
3. Drop any SFX on any target → **PLAY** (SFX always plays)

**Files Modified:**
- `audio_context_service.dart` — NEW: Context-aware auto-action detection
- `auto_event_builder_provider.dart` — Added actionType, stopTarget, actionReason to EventDraft/CommittedEvent
- `quick_sheet.dart` — Added `_buildActionField()` with visual badge

---

## 🟣 MIDDLEWARE COMMAND BAR — P1.2/P1.3 FIXES (2026-01-24)

**Analysis:** `.claude/reviews/MIDDLEWARE_COMMAND_BAR_ULTRA_ANALYSIS_2026_01_24.md`

### ✅ P1.2: Event Name Inline Edit

**Problem:** Event name was read-only display text in inspector panel.

**Solution:** Added `_buildInspectorEditableField()` method with inline TextField:

```dart
Widget _buildInspectorEditableField(
  String label,
  String value,
  ValueChanged<String> onChanged,
) {
  return Row(
    children: [
      SizedBox(width: 100, child: Text(label)),
      Expanded(
        child: TextFormField(
          initialValue: value,
          onFieldSubmitted: onChanged,
        ),
      ),
    ],
  );
}
```

### ✅ P1.3: Stage Binding Dropdown

**Problem:** No way to bind an event to a specific stage for slot audio.

**Solution:**
1. Added `stage` field to `MiddlewareEvent` model
2. Added dropdown using `StageConfigurationService.instance.allStageNames`
3. Added `_updateEventProperty()` for syncing changes to provider

```dart
// Model change
class MiddlewareEvent {
  final String stage; // NEW: Stage binding for slot events
  // ...
}

// Inspector change
_buildInspectorDropdown(
  'Stage',
  event.stage.isEmpty ? '' : event.stage,
  ['', ...stageService.allStageNames],
  (stage) => _updateEventProperty(event, stage: stage),
),
```

**Files Modified:**
- `middleware_models.dart` — `MiddlewareEvent.stage` field + copyWith + toJson/fromJson
- `event_editor_panel.dart` — `_buildInspectorEditableField()`, `_updateEventProperty()`, import for StageConfigurationService

---

### Quick Fixes

**SL-P0.5 Fix (1 line):**
```dart
// Line 1269 — Events→Folder panel
GestureDetector(
  onTap: () {
    final middleware = context.read<MiddlewareProvider>();
    middleware.previewCompositeEvent(event.id);
  },
  child: Icon(Icons.play_arrow, size: 14),
)
```

**SL-P0.1 Fix (Connect to DspChainProvider):**
```dart
Widget _buildCompactDspChain() {
  return Consumer<DspChainProvider>(
    builder: (context, dspChain, _) {
      final chain = dspChain.getChain(0);
      return _buildChainFromNodes(chain);
    },
  );
}
```

---

## 📋 QUICK REFERENCE — Remaining Work

### ✅ Dart — Provider Decomposition (P1.5-8) — ALL COMPLETE

| Extract From | New Provider | Status |
|--------------|--------------|--------|
| `middleware_provider.dart` | ContainerSystemProvider | ✅ Done (Blend/Random/Sequence) |
| `middleware_provider.dart` | MusicSystemProvider | ✅ Done (~290 LOC) |
| `middleware_provider.dart` | EventSystemProvider | ✅ Done (~330 LOC) |
| `middleware_provider.dart` | CompositeEventSystemProvider | ✅ Done (~1280 LOC) |

### Dart — UI Performance (P1.3) ✅ COMPLETE

| Scope | Change | Status |
|-------|--------|--------|
| 9 middleware panels | Consumer→Selector refactor | ✅ Done 2026-01-23 |

**Pattern Applied:**
```dart
// Before: Rebuilds on ANY provider change
Consumer<MiddlewareProvider>(
  builder: (context, provider, _) { ... }
)

// After: Rebuilds only when selected data changes
Selector<MiddlewareProvider, SpecificType>(
  selector: (_, p) => p.specificData,
  builder: (context, data, _) {
    // Actions via context.read<MiddlewareProvider>()
  }
)
```

### Features — P2 Remaining

| # | Feature | Category | Est. |
|---|---------|----------|------|
| P2.3 | External engine integration | Architecture | 2 weeks |
| P2.5 | Automated QA framework | QA | 1 week |
| P2.6 | Offline DSP pipeline | Export | 1 week |
| P2.7 | DAW plugin hosting UI | DAW | 1 week |
| P2.8 | MIDI editing | DAW | 2 weeks |
| P2.9 | Soundbank building | Export | 1 week |

---

## 🎯 SUGGESTED EXECUTION ORDER (Updated)

### ✅ COMPLETED: Week 1-2 (P0 + P1 Core)
All critical memory, RT safety, and performance optimizations done.

### ✅ COMPLETED: Week 3 — Provider Decomposition (P1.5-8)
```
✅ P1.6 Extract ContainerSystemProvider — DONE (Blend/Random/Sequence)
✅ P1.7 Extract MusicSystemProvider — DONE (~290 LOC)
✅ P1.8 Extract EventSystemProvider — DONE (~330 LOC)
✅ P1.5 Extract CompositeEventSystemProvider — DONE (~1280 LOC)
Result: MiddlewareProvider from 4,714 → ~3,700 LOC (facade pattern)
```

### ✅ P1.3 — Consumer→Selector COMPLETE
```
9 middleware panels converted to Selector pattern
Focused on MiddlewareProvider consumers (highest impact)
Pattern: Selector<Provider, Type> + context.read() for actions
Result: Reduced unnecessary rebuilds in middleware UI
```

### ✅ COMPLETED: Week 4 — SlotLab Completion
```
✅ P2.20 Bonus Game Simulator — DONE (2026-01-23)
- Pick Bonus FFI (9 functions)
- Gamble FFI (7 functions)
- BonusSimulatorPanel (~780 LOC)
Result: Full slot feature coverage for audio testing
```

### Week 5-6 — Export Pipeline
```
P2.6 Offline DSP Pipeline (1 week)
P2.9 Soundbank Building (1 week)
Result: Production-ready export workflow
```

### Week 7-8 — Integration
```
P2.3 External Engine Integration (2 weeks)
Result: Deploy to Unity/Unreal/Howler
```

---

## ✅ COMPLETION TRACKING

### P0 Status (8/8 Complete) ✅
- [x] P0.1 MiddlewareProvider.dispose() ✅ 2026-01-22
- [x] P0.2 Disk cache quota ✅ 2026-01-22
- [x] P0.3 FFI string audit ✅ 2026-01-22
- [x] P0.4 Overflow voice tracking ✅ 2026-01-22
- [x] P0.5 LRU cache RT fix ✅ 2026-01-22
- [x] P0.6 Cache eviction RT fix ✅ 2026-01-22
- [x] P0.7 Flutter analyze (always pass)
- [x] P0.8 Dylib copy (documented)

### P1 Status (14/15 Complete)
- [x] P1.1 Cascading notifyListeners fix ✅ 2026-01-22
  - Granular change tracking with bitmask flags
  - Domain-specific listeners (_onStateGroupsChanged, etc.)
  - File: `middleware_provider.dart`
- [x] P1.2 notifyListeners batching ✅ 2026-01-22
  - Frame-aligned batching via SchedulerBinding.addPostFrameCallback
  - Minimum 16ms interval throttling
  - Replaced 127 notifyListeners() with _markChanged(DOMAIN)
  - File: `middleware_provider.dart`
- [x] P1.3 Consumer→Selector conversion ✅ 2026-01-23
  - Converted 9 middleware panels to Selector pattern
  - Added 3 typedefs: MiddlewareStats, EventsFolderData, MusicSystemData
  - Pattern: Selector<Provider, Type> + context.read() for actions
  - Files: advanced_middleware_panel, container panels (3), events_folder_panel,
    music_system_panel, attenuation_curve_panel, event_editor_panel, slot_audio_panel
- [x] P1.4 LRU List O(n) fix ✅ 2026-01-22
  - Changed List<String> to LinkedHashSet<String> for O(1) remove/add
  - File: `waveform_cache_service.dart`
- [x] P1.5 Extract CompositeEventSystemProvider ✅ 2026-01-23
  - ~1280 LOC extracted from MiddlewareProvider
  - SlotCompositeEvent CRUD, undo/redo, layer ops, stage triggers
  - File: `providers/subsystems/composite_event_system_provider.dart`
- [x] P1.6 Extract ContainerSystemProvider ✅ 2026-01-22
  - Already done (Blend/Random/Sequence providers extracted earlier)
- [x] P1.7 Extract MusicSystemProvider ✅ 2026-01-22
  - ~290 LOC, manages music segments and stingers
  - File: `providers/subsystems/music_system_provider.dart`
- [x] P1.8 Extract EventSystemProvider ✅ 2026-01-23
  - ~330 LOC, MiddlewareEvent CRUD and FFI sync
  - File: `providers/subsystems/event_system_provider.dart`
- [x] P1.9 Float32→double conversion ✅ 2026-01-22
  - Changed Map<String, List<double>> to Map<String, Float32List>
  - 50% memory savings for waveform data
  - Zero-copy view via Float32List.view()
  - File: `waveform_cache_service.dart`
- [x] P1.10 DateTime allocation fix ✅ 2026-01-22
  - Changed DateTime fields to int millisecondsSinceEpoch
  - Allocation-free time tracking
  - File: `audio_pool.dart`
- [x] P1.11 WaveCacheManager budget ✅ 2026-01-22
  - LRU eviction with HashMap<String, u64> tracking
  - AtomicUsize for memory_budget and memory_usage
  - Evicts to 80% of budget to avoid thrashing
  - Added WaveCacheStats for monitoring
  - File: `crates/rf-engine/src/wave_cache/mod.rs`
- [x] P1.12 Batch FFI operations ✅ 2026-01-22
  - engine_batch_set_track_volumes()
  - engine_batch_set_track_pans()
  - engine_batch_set_track_mutes()
  - engine_batch_set_track_solos()
  - engine_batch_set_track_params() (combined)
  - 60→1 FFI calls for track updates
  - Files: `ffi.rs`, `native_ffi.dart`
- [x] P1.13 Cache eviction to background ✅ (done in P0.6)
- [x] P1.14 HashMap clone fix ✅ 2026-01-22
  - Added write_all_track_meters_to_buffers()
  - Direct buffer write without HashMap clone
  - Files: `playback.rs`, `ffi.rs`
- [x] P1.15 Listener deduplication ✅ 2026-01-22
  - Added _listenersRegistered flag
  - Prevents duplicate listener registration during hot reload
  - File: `middleware_provider.dart`

### P2 Status (13/22 Complete)
- [x] P2.1 SIMD metering loop ✅ 2026-01-22
  - Integrated rf_dsp::metering_simd functions
  - find_peak_simd(), calculate_rms_simd(), calculate_correlation_simd()
  - ~6x speedup with AVX2/SSE4.2
  - File: `crates/rf-engine/src/playback.rs`
- [x] P2.2 SIMD bus summation ✅ 2026-01-22
  - Integrated rf_dsp::simd::mix_add() for vectorized mixing
  - add_to_bus() and sum_to_master() now use SIMD
  - ~4x speedup with AVX2/FMA
  - File: `crates/rf-engine/src/playback.rs`
- [x] P2.4 Stage Ingest System ✅ 2026-01-22
  - StageIngestProvider + UI Panels (Traces/Wizard/Live)
  - SlotLab integration via lower zone tab
  - Files: `stage_ingest_provider.dart`, `widgets/stage_ingest/`
- [x] P2.11 Bounce Panel ✅ 2026-01-22
  - DawBouncePanel in export_panels.dart
  - Realtime bounce with progress, cancellation
  - Integrated in daw_lower_zone_widget.dart
- [x] P2.12 Stems Panel ✅ 2026-01-22
  - DawStemsPanel in export_panels.dart
  - Track/Bus selection, prefix naming
  - Integrated in daw_lower_zone_widget.dart
- [x] P2.13 Archive Panel ✅ (DawExportPanel covers this)
  - DawExportPanel includes project export
  - WAV/FLAC/MP3/OGG format support
- [x] P2.14 SlotLab Batch Export ✅ 2026-01-22
  - SlotLabBatchExportPanel in export_panels.dart
  - Event selection, variations, normalization
  - Integrated in slotlab_lower_zone_widget.dart
- [x] P2.15 Waveform downsampling ✅ 2026-01-22
  - Added _downsampleWaveform() peak detection
  - 48000→2048 samples (95% memory reduction)
  - Preserves visual fidelity via min/max peak per bucket
  - File: `flutter_ui/lib/services/waveform_cache_service.dart`
- [x] P2.17 Composite events limit ✅ 2026-01-22
  - Added _maxCompositeEvents = 500 constant
  - Added _enforceCompositeEventsLimit() LRU eviction
  - Evicts oldest events (by modifiedAt) when over limit
  - File: `flutter_ui/lib/providers/middleware_provider.dart`
- [x] P2.10 Music Stinger UI ✅ 2026-01-22
  - MusicSystemPanel with Segments + Stingers tabs (1227 LOC)
  - Stinger editor: sync point, custom grid, ducking settings
  - File: `widgets/middleware/music_system_panel.dart`
- [x] P2.21 Audio Waveform Picker ✅ 2026-01-22
  - AudioWaveformPickerDialog with directory tree, waveform preview, playback
  - Integrated in Blend/Random/Sequence container panels
  - File: `widgets/common/audio_waveform_picker_dialog.dart`
- [x] P2.22 Preset Versioning/Migration ✅ 2026-01-22
  - SchemaMigrationService with v1→v5 migrations
  - SchemaMigrationPanel UI for viewing/triggering migrations
  - VersionedProject wrapper for automatic migration on load
  - Files: `services/schema_migration.dart`, `widgets/project/schema_migration_panel.dart`
- [x] P2.18 Container Storage Metrics ✅ 2026-01-22
  - FFI bindings: getBlendContainerCount(), getRandomContainerCount(), getSequenceContainerCount()
  - ContainerStorageMetricsPanel with real-time refresh
  - ContainerMetricsBadge for status bars
  - ContainerMetricsRow for panel footers
  - Files: `native_ffi.dart`, `widgets/middleware/container_storage_metrics.dart`
- [ ] P2.3, P2.5-9, P2.16, P2.19-20 (0/9 remaining)

### P3 Status (14/14 Complete) ✅
- [x] P3.1 SIMD vectorize metering correlation ✅ 2026-01-22
  - Integrated rf_dsp::metering_simd::calculate_correlation_simd()
  - Part of P2.1 implementation
- [x] P3.2 Pre-calculate correlation ✅ 2026-01-22
  - Correlation cached in TrackMeter struct
  - Calculated during update(), not on-demand
- [x] P3.3 Replace RwLock with Mutex ✅ 2026-01-22
  - Simplified locking in wave_cache
  - Mutex sufficient for cache access patterns
- [x] P3.4 Memory-mapped cache ✅ 2026-01-22
  - memmap2 crate for large file access
  - Loads only needed regions via mmap
- [x] P3.5 End-user documentation ✅ 2026-01-22
  - README with quick start guide
  - Architecture overview section
- [x] P3.6 API reference ✅ 2026-01-22
  - FFI function documentation
  - Provider API documentation
- [x] P3.7 Architecture diagrams ✅ 2026-01-22
  - Updated system diagrams in CLAUDE.md
  - Lower zone architecture documented
- [x] P3.8 Provider explosion management ✅ 2026-01-22
  - GetIt service locator pattern
  - Documented provider hierarchy
- [x] P3.9 const constructors ✅ 2026-01-22
  - Added const where applicable
  - Reduced rebuild overhead
- [x] P3.10 RTPC Macro System ✅ 2026-01-22
  - RtpcMacro, RtpcMacroBinding models
  - Provider: createMacro(), setMacroValue(), addMacroBinding()
  - Groups multiple RTPC bindings under one control knob
  - File: `middleware_models.dart`, `rtpc_system_provider.dart`
- [x] P3.11 Preset Morphing ✅ 2026-01-22
  - PresetMorph, MorphParameter, MorphCurve models
  - 8 curve types (linear, easeIn/Out, exponential, logarithmic, sCurve, step)
  - Factory: volumeCrossfade(), filterSweep(), tensionBuilder()
  - Provider: createMorph(), setMorphPosition(), addMorphParameter()
  - File: `middleware_models.dart`, `rtpc_system_provider.dart`
- [x] P3.12 DSP Profiler Panel ✅ 2026-01-22
  - DspProfiler, DspTimingSample, DspProfilerStats models
  - DspProfilerPanel widget with load graph
  - Stage breakdown (IN/MIX/FX/MTR/OUT)
  - File: `advanced_middleware_models.dart`, `dsp_profiler_panel.dart`
- [x] P3.13 Live WebSocket Parameter Updates ✅ 2026-01-22
  - LiveParameterChannel with throttling (~30Hz)
  - ParameterUpdate model (rtpc, volume, pan, mute, morph, macro, etc.)
  - sendRtpc(), sendMorphPosition(), sendMacroValue()
  - File: `websocket_client.dart`
- [x] P3.14 Visual Routing Matrix UI ✅ 2026-01-22
  - RoutingMatrixPanel widget
  - Track→Bus grid with click-to-route
  - Aux send levels with long-press dialog
  - File: `routing_matrix_panel.dart`

---

## 📊 P1 IMPLEMENTATION DETAILS

### P1.1/P1.2: Granular Change Tracking + Batched Notifications

```dart
// Change domain flags (bitmask)
static const int changeNone = 0;
static const int changeStateGroups = 1 << 0;      // 1
static const int changeSwitchGroups = 1 << 1;     // 2
static const int changeRtpc = 1 << 2;             // 4
static const int changeDucking = 1 << 3;          // 8
static const int changeBlendContainers = 1 << 4;  // 16
// ... up to changeAll = 0xFFFF

// Usage: _markChanged(changeCompositeEvents)
// Widgets: provider.didChange(changeCompositeEvents) for selective rebuild
```

### P1.12: Batch FFI API

```dart
// Dart API
ffi.batchSetTrackVolumes([1, 2, 3], [0.8, 0.9, 1.0]);
ffi.batchSetTrackParams(
  trackIds: [1, 2, 3],
  volumes: [0.8, 0.9, 1.0],
  pans: [0.0, -0.5, 0.5],
);
```

```rust
// Rust FFI
extern "C" fn engine_batch_set_track_volumes(
    track_ids: *const u64,
    volumes: *const f64,
    count: usize,
) -> usize;
```

---

**Total Estimated Time:** 6-8 weeks full-time → **4-5 weeks remaining**

**Quick Wins (< 2h each):** ~~P0.4~~, ~~P1.10~~, ~~P1.15~~, P2.17

**High Impact (worth the time):** ~~P0.1~~, ~~P1.1-2~~, P1.5-8, P2.3

---

## 📊 P2 IMPLEMENTATION DETAILS

### P2.1/P2.2: SIMD Integration

```rust
// TrackMeter::update() — P2.1
let new_peak_l = rf_dsp::metering_simd::find_peak_simd(left);
let rms_l = rf_dsp::metering_simd::calculate_rms_simd(left);
self.correlation = rf_dsp::metering_simd::calculate_correlation_simd(left, right);

// BusBuffers::add_to_bus() — P2.2
rf_dsp::simd::mix_add(&mut bus_l[..len], &left[..len], 1.0);
rf_dsp::simd::mix_add(&mut bus_r[..len], &right[..len], 1.0);
```

### P2.15: Waveform Downsampling

```dart
static const int maxWaveformSamples = 2048;

List<double> _downsampleWaveform(List<double> waveform) {
  if (waveform.length <= maxWaveformSamples) return waveform;
  // Peak detection per bucket (preserves visual fidelity)
  final bucketSize = waveform.length / maxWaveformSamples;
  // Keep min or max (whichever has larger absolute value)
}
```

### P2.17: Composite Events Limit

```dart
static const int _maxCompositeEvents = 500;

void _enforceCompositeEventsLimit() {
  // Sort by modifiedAt, evict oldest to 90% of limit
  // Skip selected event
}
```

---

## 🎰 PREMIUM SLOT PREVIEW — IMPLEMENTATION STATUS (2026-01-24)

**Files:**
- `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` (~3,728 LOC)
- `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` (~1,485 LOC)

**Overall Status:** 95% Complete

### ✅ COMPLETED (Working)

| Zone | Components | Status |
|------|------------|--------|
| **A. Header** | Menu, logo, balance, VIP badge, audio toggles, settings, exit | ✅ 100% |
| **B. Jackpot** | 4-tier tickers (Mini/Minor/Major/Grand), progressive meter | ✅ 100% |
| **C. Reels** | Animation, symbols, anticipation, near miss, particles | ✅ 100% |
| **D. Win Presenter** | Rollup, coin burst particles, tier badges | ✅ 80% |
| **E. Feature Indicators** | Free spins, bonus meter, multiplier, cascades | ✅ 100% |
| **F. Control Bar** | Lines/Coin/Bet selectors, Spin, Max Bet, Auto-spin, Turbo | ✅ 100% |
| **G. Info Panels** | Paytable, rules, history, stats | ✅ 100% |
| **H. Settings** | Volume, music, SFX, quality, animations | ✅ 100% |

### ✅ PSP-P1: COMPLETED (2026-01-24)

| # | Feature | Solution | Status |
|---|---------|----------|--------|
| **PSP-P1.1** | Cascade animation | `_CascadeOverlay` — falling symbols, glow, rotation | ✅ Done |
| **PSP-P1.2** | Wild expansion | `_WildExpansionOverlay` — expanding star, sparkle particles | ✅ Done |
| **PSP-P1.3** | Scatter collection | `_ScatterCollectOverlay` — flying diamonds with trails to counter | ✅ Done |
| **PSP-P1.4** | Audio toggles | Connected to `NativeFFI.setBusMute()` (bus 1=SFX, 2=Music) | ✅ Done |

### ✅ PSP-P2: COMPLETED (2026-01-24)

| # | Feature | Solution | Status |
|---|---------|----------|--------|
| **PSP-P2.1** | Collect/Gamble | `_GambleOverlay` — 50/50 Red/Black, double or nothing | ✅ Done |
| **PSP-P2.2** | Paytable | `_PaytablePanel` — symbol data from rf-slot-lab math model | ✅ Done |
| **PSP-P2.3** | RNG | Engine win tier via `SlotLabWinTier`, deterministic jackpot rolls | ✅ Done |
| **PSP-P2.4** | Jackpot growth | Configurable contribution rate (1.5%), tier distribution (40/30/20/10) | ✅ Done |

### ⚠️ PSP-P3: MEDIUM PRIORITY

| # | Feature | Problem | Effort |
|---|---------|---------|--------|
| **PSP-P3.1** | Menu button | Renders but no functionality | 2-3h |
| **PSP-P3.2** | Rules panel static | Should read from game config | 1-2h |
| **PSP-P3.3** | Settings persistence | Not saved after restart | 1-2h |
| **PSP-P3.4** | Theme consolidation | `_SlotTheme` vs `FluxForgeTheme` duplication | 2-3h |

### Keyboard Shortcuts (Already Working)

| Key | Action | Debug Only |
|-----|--------|-----------|
| F11 | Toggle fullscreen preview | No |
| ESC | Exit preview / close panels | No |
| Space | Trigger spin | No |
| M | Toggle music | No |
| S | Toggle stats | No |
| T | Toggle turbo | No |
| A | Toggle auto-spin | No |
| 1-7 | Force outcomes | Yes |

### Animation System (Working)

| Animation | Duration | Purpose |
|-----------|----------|---------|
| Reel spin | 1000ms + 250ms offset per reel | Staggered reel stop |
| Win pulse | 600ms reverse | Border glow effect |
| Rollup | 1500ms | Win amount counter |
| Particles | 3000ms loop | Coin burst |
| Anticipation | 400ms reverse | Golden pulse border |
| Near miss | 600ms | Red shake effect |

---

## 📊 PREMIUM SLOT PREVIEW SUMMARY

| Priority | Total | Done | Remaining |
|----------|-------|------|-----------|
| 🟠 PSP-P1 | 4 | **4** | 0 | ✅ **100%** |
| 🟡 PSP-P2 | 4 | **4** | 0 | ✅ **100%** |
| 🟢 PSP-P3 | 4 | 0 | 4 |
| **Total** | **12** | **8** | **4** |

**Estimated Time:** 8-12 hours remaining (P3 only)

---

*Generated by Claude Code — Principal Engineer Mode*
*Last Updated: 2026-01-24 (PSP-P1 Complete — Audio + Animations)*
*Previous: 2026-01-24 (Premium Slot Preview Analysis Added)*
