# P3.8 Provider Explosion Audit

**Date:** 2026-01-22
**Total Providers Found:** 108

---

## Executive Summary

FluxForge Studio has **108 provider files**, which is significantly above the recommended 20-30 for a project of this size. This creates:

1. **Maintenance complexity** — Hard to track which provider manages what
2. **Dependency hell** — Providers depend on other providers
3. **Performance overhead** — Each provider adds listener overhead
4. **Testing difficulty** — Complex mocking requirements

---

## Provider Categories

### Core Engine (8)

| Provider | LOC | Status | Notes |
|----------|-----|--------|-------|
| `engine_provider.dart` | ~200 | Keep | Core FFI state |
| `timeline_playback_provider.dart` | ~400 | Keep | Transport control |
| `mixer_provider.dart` | ~350 | Keep | DAW mixer |
| `mixer_dsp_provider.dart` | ~300 | Keep | Middleware mixer |
| `meter_provider.dart` | ~250 | Keep | Real-time metering |
| `automation_provider.dart` | ~500 | Keep | Parameter automation |
| `control_room_provider.dart` | ~200 | Keep | Monitor control |
| `input_bus_provider.dart` | ~150 | Keep | Recording inputs |

### Middleware System (12)

| Provider | LOC | Status | Notes |
|----------|-----|--------|-------|
| `middleware_provider.dart` | 4714 | **DECOMPOSE** | Too large |
| `ale_provider.dart` | ~745 | Keep | ALE system |
| `slot_lab_provider.dart` | ~800 | Keep | Slot simulation |
| `stage_provider.dart` | ~200 | Keep | Stage events |

**Subsystem Providers (extracted from MiddlewareProvider):**
| Provider | LOC | Status |
|----------|-----|--------|
| `state_groups_provider.dart` | ~185 | ✅ Extracted |
| `switch_groups_provider.dart` | ~210 | ✅ Extracted |
| `rtpc_system_provider.dart` | ~350 | ✅ Extracted |
| `ducking_system_provider.dart` | ~190 | ✅ Extracted |
| `blend_containers_provider.dart` | ~200 | ✅ Extracted |
| `random_containers_provider.dart` | ~200 | ✅ Extracted |
| `sequence_containers_provider.dart` | ~200 | ✅ Extracted |

### Timeline/Editing (15)

| Provider | LOC | Status | Notes |
|----------|-----|--------|-------|
| `arranger_track_provider.dart` | ~400 | Keep | |
| `track_versions_provider.dart` | ~200 | Keep | |
| `comping_provider.dart` | ~300 | Keep | |
| `clip_gain_envelope_provider.dart` | ~200 | Keep | |
| `tempo_track_provider.dart` | ~250 | Keep | |
| `chord_track_provider.dart` | ~200 | Keep | |
| `groove_quantize_provider.dart` | ~150 | Keep | |
| `audio_alignment_provider.dart` | ~200 | Keep | |
| `scale_assistant_provider.dart` | ~150 | Keep | |
| `expression_map_provider.dart` | ~200 | Keep | |
| `marker_track_provider.dart` | ~150 | Keep | |
| `ruler_provider.dart` | ~100 | Keep | |
| `grid_provider.dart` | ~100 | Keep | |
| `snap_provider.dart` | ~100 | Keep | |
| `zoom_provider.dart` | ~100 | Keep | |

### Plugin System (5)

| Provider | LOC | Status | Notes |
|----------|-----|--------|-------|
| `plugin_provider.dart` | ~500 | Keep | |
| `plugin_scan_provider.dart` | ~200 | Keep | |
| `plugin_parameter_provider.dart` | ~200 | Keep | |
| `plugin_preset_provider.dart` | ~150 | Keep | |
| `plugin_state_provider.dart` | ~150 | Keep | |

### Project/Session (8)

| Provider | LOC | Status | Notes |
|----------|-----|--------|-------|
| `session_persistence_provider.dart` | ~300 | Keep | |
| `auto_save_provider.dart` | ~150 | Keep | |
| `recent_projects_provider.dart` | ~100 | Keep | |
| `undo_manager.dart` | ~400 | Keep | Not a provider but related |
| `project_settings_provider.dart` | ~200 | Keep | |
| `project_metadata_provider.dart` | ~100 | Keep | |
| `file_browser_provider.dart` | ~200 | Keep | |
| `asset_manager_provider.dart` | ~300 | Keep | |

### UI State (20+)

Many small providers for UI state:
- `editor_mode_provider.dart`
- `lower_zone_controller.dart`
- `split_view_provider.dart`
- Various panel visibility providers

---

## Recommendations

### 1. Consolidate UI State Providers

**Before:**
```
editor_mode_provider.dart
lower_zone_visibility_provider.dart
upper_zone_visibility_provider.dart
split_view_provider.dart
panel_state_provider.dart
```

**After:**
```
ui_layout_provider.dart  // Consolidates all UI layout state
```

### 2. Use Riverpod Instead of Provider

Riverpod offers:
- Compile-time safety
- No BuildContext required
- Better dependency management
- Automatic disposal

### 3. Complete MiddlewareProvider Decomposition

Remaining extractions needed:
- ContainerSystemProvider (Blend + Random + Sequence)
- MusicSystemProvider (Music segments, stingers)
- EventSystemProvider (Composite events, event registry sync)

### 4. Implement Provider Facade Pattern

Create facade providers that aggregate related state:

```dart
class TimelineProvider extends ChangeNotifier {
  final TransportProvider _transport;
  final ZoomProvider _zoom;
  final GridProvider _grid;
  final SnapProvider _snap;

  // Unified API
}
```

### 5. Move Pure State to ValueNotifier

Providers that only hold primitive state:

```dart
// Before
class ZoomProvider extends ChangeNotifier {
  double _zoom = 1.0;
  double get zoom => _zoom;
  set zoom(double v) { _zoom = v; notifyListeners(); }
}

// After
final zoomNotifier = ValueNotifier<double>(1.0);
```

---

## Action Items

| Priority | Task | Est. |
|----------|------|------|
| P1 | Consolidate 20+ UI state providers into 5 | 8h |
| P1 | Complete MiddlewareProvider decomposition | 6h |
| P2 | Implement provider facades | 4h |
| P2 | Convert trivial providers to ValueNotifier | 4h |
| P3 | Evaluate Riverpod migration | 2w |

---

## Target State

| Category | Current | Target |
|----------|---------|--------|
| Total Providers | 108 | 40-50 |
| UI State Providers | 25+ | 5-8 |
| MiddlewareProvider LOC | 4714 | <500 |

---

*Generated by Claude Code — P3.8 Provider Audit*
