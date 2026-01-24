# Middleware TODO — M3 Sprint Plan

**Datum:** 2026-01-23
**Izvor:** MIDDLEWARE_ANALYSIS_BY_ROLES_2026_01_23.md
**Status:** M3.1 COMPLETED ✅ | M3.2 COMPLETED ✅ | M4 COMPLETED ✅
**M3.1 Completed:** 2026-01-23
**M3.2 Completed:** 2026-01-23
**M4 Completed:** 2026-01-23

---

## 🔴 P1 — HIGH PRIORITY (This Sprint) — ✅ ALL COMPLETED

### TODO 1: RTPC Debugger Panel ✅ DONE
**Uloge:** Audio Middleware Architect, Engine Developer
**Problem:** Nema real-time monitoring RTPC vrednosti

| Task | Lokacija | LOC est |
|------|----------|---------|
| Create `rtpc_debugger_panel.dart` | `flutter_ui/lib/widgets/middleware/` | ~600 |
| Add real-time value meters | Widget | — |
| Add curve visualization with current position marker | Widget | — |
| Add RTPC history sparkline graph | Widget | — |
| Integrate with RtpcSystemProvider | Provider hook | — |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/widgets/middleware/rtpc_debugger_panel.dart
```

**Fajlovi za modifikaciju:**
```
flutter_ui/lib/widgets/middleware/middleware_exports.dart  → Add export
flutter_ui/lib/providers/subsystems/rtpc_system_provider.dart → Add value stream
```

---

### TODO 2: Tab Categories u Lower Zone ✅ DONE
**Uloge:** UX Designer
**Problem:** 15+ tabova bez logičkog grupiranja

| Task | Lokacija | LOC est |
|------|----------|---------|
| Define tab categories enum | `lower_zone_controller.dart` | ~30 |
| Create collapsible category headers | `slot_lab_screen.dart` | ~100 |
| Group tabs: [Audio] [Routing] [Debug] [Advanced] | UI logic | — |
| Add category collapse/expand state | Controller | — |

**Kategorije:**
```dart
enum LowerZoneCategory {
  audio,    // Events, Containers (Blend/Random/Sequence), Music
  routing,  // Buses, Ducking, Aux Sends
  debug,    // Profiler, Voice Pool, Memory, DSP Load
  advanced, // AutoSpatial, Stage Ingest, ALE
}
```

**Fajlovi za modifikaciju:**
```
flutter_ui/lib/controllers/slot_lab/lower_zone_controller.dart
flutter_ui/lib/screens/slot_lab_screen.dart
```

---

### TODO 3: Trace Export (Full) ✅ DONE
**Uloge:** QA Engineer
**Problem:** Nema export event trace-a za offline analysis

| Task | Lokacija | LOC est |
|------|----------|---------|
| Add `exportToCSV()` method | `event_profiler_provider.dart` | ~50 |
| Add export button to Event Profiler Panel | `event_profiler_panel.dart` | ~30 |
| Add file save dialog | Widget | ~20 |
| Include all fields: timestamp, type, latency, bus, voice | Export logic | — |

**Fajlovi za modifikaciju:**
```
flutter_ui/lib/providers/subsystems/event_profiler_provider.dart → Add exportToCSV
flutter_ui/lib/widgets/middleware/event_profiler_panel.dart → Add export UI
```

**CSV Format:**
```csv
timestamp,eventId,type,description,soundId,busId,voiceId,latencyUs
2026-01-23T12:34:56.789,1,voiceStart,SPIN_START,101,2,5,450
```

---

## 🟡 P2 — MEDIUM PRIORITY (Next Sprint) — ✅ ALL COMPLETED

### TODO 4: Inline Waveform Actions ✅ DONE
**Uloge:** Audio Designer
**Problem:** Nema trim/fade editing bez eksternog alata

| Task | Lokacija | LOC est |
|------|----------|---------|
| Add trim handles to waveform display | `waveform_painter.dart` | ~150 |
| Add fade in/out curve handles | Painter | ~100 |
| Implement non-destructive trim (store start/end offset) | Model | ~50 |
| Add right-click context menu | Widget | ~80 |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/widgets/common/waveform_trim_editor.dart
```

**Fajlovi za modifikaciju:**
```
flutter_ui/lib/models/slot_audio_events.dart → Add trimStart, trimEnd, fadeIn, fadeOut
flutter_ui/lib/widgets/slot_lab/layer_timeline_panel.dart → Integrate editor
```

---

### TODO 5: Ducking Preview Mode ✅ DONE
**Uloge:** Audio Middleware Architect
**Problem:** Ne može testirati ducking bez full mix

| Task | Lokacija | LOC est |
|------|----------|---------|
| Add "Preview" button to DuckingMatrixPanel | `ducking_matrix_panel.dart` | ~50 |
| Create preview audio generator (sine/noise) | Service | ~100 |
| Show visual ducking curve during preview | Widget | ~150 |
| Integrate with DuckingService | Service hook | ~50 |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/services/ducking_preview_service.dart
```

**Fajlovi za modifikaciju:**
```
flutter_ui/lib/widgets/middleware/ducking_matrix_panel.dart
flutter_ui/lib/services/ducking_service.dart → Add preview mode
```

---

### TODO 6: Workspace Presets ✅ DONE
**Uloge:** UX Designer
**Problem:** Nema save/load panel konfiguracije

| Task | Lokacija | LOC est |
|------|----------|---------|
| Create WorkspacePreset model | Models | ~50 |
| Create WorkspacePresetService | Service | ~150 |
| Add preset dropdown to lower zone header | Widget | ~80 |
| Include: active tabs, expanded state, heights | Data | — |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/models/workspace_preset.dart
flutter_ui/lib/services/workspace_preset_service.dart
```

**Preset Examples:**
```json
{
  "name": "Audio Design",
  "tabs": ["events", "blend", "random", "sequence"],
  "expandedCategories": ["audio"],
  "heights": {"lowerZone": 350}
}
```

---

## 🟢 P3 — LOW PRIORITY (Future)

### TODO 7: Spectrum Analyzer
**Uloge:** DSP Engineer
**Problem:** Nema frequency content visualization

| Task | Lokacija | LOC est |
|------|----------|---------|
| Create FFT display widget | `spectrum_analyzer_widget.dart` | ~400 |
| Integrate with bus metering FFI | FFI | ~100 |
| Add to Bus Hierarchy Panel | Widget integration | ~50 |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/widgets/dsp/spectrum_analyzer_widget.dart
crates/rf-bridge/src/metering_ffi.rs → Add FFT export
```

---

### TODO 8: Determinism Mode
**Uloge:** QA Engineer
**Problem:** Random containers nisu reproducibilni

| Task | Lokacija | LOC est |
|------|----------|---------|
| Add seed parameter to RandomContainer | Model | ~20 |
| Implement seeded random selection | Container logic | ~50 |
| Add "Deterministic Mode" toggle | Settings | ~30 |
| Store seed in event trace | Profiler | ~20 |

**Fajlovi za modifikaciju:**
```
flutter_ui/lib/models/middleware_models.dart → RandomContainer.seed
flutter_ui/lib/providers/subsystems/random_containers_provider.dart
crates/rf-engine/src/containers/random.rs → Seeded selection
```

---

### TODO 9: Math Model Connector
**Uloge:** Slot Game Designer
**Problem:** Win tier pragovi disconnected od audio

| Task | Lokacija | LOC est |
|------|----------|---------|
| Create WinTierConfig model | Models | ~80 |
| Auto-generate RTPC thresholds from paytable | Service | ~150 |
| Link to Attenuation Curves | Integration | ~50 |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/models/win_tier_config.dart
flutter_ui/lib/services/math_model_connector.dart
```

---

### TODO 10: Interactive Tutorials
**Uloge:** Producer
**Problem:** Steep learning curve

| Task | Lokacija | LOC est |
|------|----------|---------|
| Create tutorial overlay system | Widget | ~300 |
| Write "First Event" tutorial | Content | — |
| Write "RTPC Setup" tutorial | Content | — |
| Add tutorial launcher to Help menu | UI | ~50 |

**Fajlovi za kreiranje:**
```
flutter_ui/lib/widgets/tutorial/tutorial_overlay.dart
flutter_ui/lib/widgets/tutorial/tutorial_step.dart
flutter_ui/lib/data/tutorials/first_event_tutorial.dart
```

---

## 📊 Summary Table

| # | Task | Priority | LOC | Sprint | Status |
|---|------|----------|-----|--------|--------|
| 1 | RTPC Debugger Panel | P1 | ~1159 | M3.1 | ✅ DONE |
| 2 | Tab Categories | P1 | ~100 | M3.1 | ✅ DONE |
| 3 | Trace Export CSV | P1 | ~85 | M3.1 | ✅ DONE |
| 4 | Waveform Trim Editor | P2 | ~380 | M3.2 | ✅ DONE |
| 5 | Ducking Preview | P2 | ~380 | M3.2 | ✅ DONE |
| 6 | Workspace Presets | P2 | ~830 | M3.2 | ✅ DONE |
| 7 | Spectrum Analyzer | P3 | ~1334 | M4 | ✅ DONE (already existed) |
| 8 | Determinism Mode | P3 | ~120 | M4 | ✅ DONE |
| 9 | Math Model Connector | P3 | ~480 | M4 | ✅ DONE |
| 10 | Interactive Tutorials | P3 | ~550 | M4 | ✅ DONE |

**Total Estimated:** ~5,418 LOC
**M3.1 Completed:** ~1,344 LOC (3/10 tasks)
**M3.2 Completed:** ~1,590 LOC (6/10 tasks)
**M4 Completed:** ~2,484 LOC (10/10 tasks) ✅ ALL DONE

---

## ✅ Already Done (Reference)

| Feature | File | Status |
|---------|------|--------|
| State Machine Graph | `state_machine_graph.dart` | ✅ Complete |
| Command Palette | `command_palette.dart` | ✅ Complete |
| Container Visualization | `container_visualization_widgets.dart` | ✅ Complete |
| Voice Pool Stats | `voice_pool_stats_panel.dart` | ✅ Complete |
| DSP Profiler | `dsp_profiler_panel.dart` | ✅ Complete |
| Event Profiler JSON Export | `event_profiler_provider.dart` | ✅ Complete |
| **RTPC Debugger Panel** | `rtpc_debugger_panel.dart` | ✅ M3.1 |
| **Tab Categories** | `lower_zone_controller.dart` | ✅ M3.1 |
| **Trace Export CSV** | `event_profiler_provider.dart` | ✅ M3.1 |
| **Waveform Trim Editor** | `waveform_trim_editor.dart` | ✅ M3.2 |
| **Ducking Preview** | `ducking_preview_service.dart`, `ducking_matrix_panel.dart` | ✅ M3.2 |
| **Workspace Presets** | `workspace_preset.dart`, `workspace_preset_service.dart`, `workspace_preset_dropdown.dart` | ✅ M3.2 |

---

## 🎯 M3.1 Sprint Scope — ✅ COMPLETED 2026-01-23

**Cilj:** 3 P1 taska (~830 LOC) — **SVE ZAVRŠENO**

```
Week 1:
- [x] RTPC Debugger Panel (1159 LOC) ✅ Already existed, exported

Week 2:
- [x] Tab Categories (100 LOC) ✅ Added to lower_zone_controller.dart
- [x] Trace Export CSV (85 LOC) ✅ Added to event_profiler_provider.dart
```

**Definition of Done:** ✅ ALL MET
1. ✅ Widget renderuje bez errora
2. ✅ Integrisan u Lower Zone
3. ✅ flutter analyze = 0 errors (11 info-level only)
4. ✅ Dokumentovano u CLAUDE.md

**Completed:** 2026-01-23
**Actual LOC:** ~1344 (vs estimated ~830)

---

## 🎯 M3.2 Sprint Scope — ✅ COMPLETED 2026-01-23

**Cilj:** 3 P2 taska (~1,010 LOC) — **SVE ZAVRŠENO**

```
- [x] Waveform Trim Editor (~380 LOC) ✅
      flutter_ui/lib/widgets/common/waveform_trim_editor.dart
      flutter_ui/lib/models/slot_audio_events.dart (trimStartMs, trimEndMs)

- [x] Ducking Preview Mode (~380 LOC) ✅
      flutter_ui/lib/services/ducking_preview_service.dart (~230 LOC)
      flutter_ui/lib/widgets/middleware/ducking_matrix_panel.dart (+150 LOC)

- [x] Workspace Presets (~830 LOC) ✅
      flutter_ui/lib/models/workspace_preset.dart (~210 LOC)
      flutter_ui/lib/services/workspace_preset_service.dart (~280 LOC)
      flutter_ui/lib/widgets/lower_zone/workspace_preset_dropdown.dart (~340 LOC)
      flutter_ui/lib/widgets/lower_zone/lower_zone_context_bar.dart (presetDropdown param)
```

**Definition of Done:** ✅ ALL MET
1. ✅ Widgets renderuju bez errora
2. ✅ Integrisani u Lower Zone / DuckingMatrixPanel
3. ✅ flutter analyze = 0 errors (11 info-level only)
4. ✅ Dokumentovano u CLAUDE.md

**Completed:** 2026-01-23
**Actual LOC:** ~1,590 (vs estimated ~1,010)

---

## 🎯 M4 Sprint Scope — ✅ COMPLETED 2026-01-23

**Cilj:** 4 P3 taska (~1,300 LOC) — **SVE ZAVRŠENO**

```
- [x] Spectrum Analyzer (already existed at widgets/spectrum/spectrum_analyzer.dart ~1334 LOC) ✅
      Full-featured FFT display with bars/line/fill/waterfall/spectrogram modes
      Integrated in BusHierarchyPanel

- [x] Determinism Mode (~120 LOC) ✅
      flutter_ui/lib/models/middleware_models.dart — RandomContainer.seed, useDeterministicMode
      flutter_ui/lib/providers/subsystems/random_containers_provider.dart — Seeded random, history

- [x] Math Model Connector (~480 LOC) ✅
      flutter_ui/lib/models/win_tier_config.dart — WinTier, WinTierThreshold, WinTierConfig
      flutter_ui/lib/services/math_model_connector.dart — RTPC generation, attenuation links

- [x] Interactive Tutorials (~550 LOC) ✅
      flutter_ui/lib/widgets/tutorial/tutorial_step.dart — TutorialStep, Tutorial models
      flutter_ui/lib/widgets/tutorial/tutorial_overlay.dart — Spotlight overlay, TutorialLauncher
      flutter_ui/lib/data/tutorials/first_event_tutorial.dart — FirstEvent, RtpcSetup tutorials
```

**Definition of Done:** ✅ ALL MET
1. ✅ Widgets renderuju bez errora
2. ✅ flutter analyze = 0 errors (11 info-level only)
3. ✅ Dokumentovano u MIDDLEWARE_TODO

**Completed:** 2026-01-23
**Actual LOC:** ~2,484 (vs estimated ~1,300)

---

## 🎯 M5 Sprint — Middleware Inspector P0 Fixes ✅ COMPLETED 2026-01-24

**Cilj:** 3 P0 critical fixes za Right Inspector Panel

```
- [x] P0.1: TextFormField Key Fix (~10 LOC) ✅
      Problem: Event name field didn't update when switching events
      Fix: Added ValueKey('event_name_${event.id}') to force rebuild
      File: event_editor_panel.dart:2346-2350

- [x] P0.2: Slider Debouncing (~35 LOC) ✅
      Problem: Excessive FFI calls during slider drag
      Fix: Added _sliderDebounceTimer with 50ms debounce
      New method: _updateActionDebounced() for slider-only updates
      File: event_editor_panel.dart:3733-3766

- [x] P0.3: Gain dB Display (~105 LOC) ✅
      Problem: Gain showed percentage instead of dB
      Fix: New _buildGainSlider() with dB conversion
      Display: -∞ dB to +6 dB with color coding
      Presets: -12dB, -6dB, 0dB, +3dB, +6dB
      File: event_editor_panel.dart:2720-2823
```

**Definition of Done:** ✅ ALL MET
1. ✅ flutter analyze = 0 errors
2. ✅ All sliders use debounced updates
3. ✅ TextFormField rebuilds on event change
4. ✅ Gain shows dB with color coding
5. ✅ Dokumentovano u CLAUDE.md

**Completed:** 2026-01-24
**Actual LOC:** ~150

---

## 🏁 ALL SPRINTS COMPLETED

| Sprint | Tasks | LOC | Status |
|--------|-------|-----|--------|
| M3.1 | 3 (P1) | ~1,344 | ✅ DONE |
| M3.2 | 3 (P2) | ~1,590 | ✅ DONE |
| M4 | 4 (P3) | ~2,484 | ✅ DONE |
| M5 | 3 (P0) | ~150 | ✅ DONE |
| **Total** | **13** | **~5,568** | **✅ ALL DONE** |
