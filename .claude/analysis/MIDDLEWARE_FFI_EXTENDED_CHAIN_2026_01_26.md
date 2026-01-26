# Middleware FFI Extended Chain — Analysis Document

**Date:** 2026-01-26
**Status:** FIXED
**Type:** Critical FFI Gap Resolution

---

## Problem Discovery

MiddlewareAction extended playback parameters were implemented in the UI layer but NOT connected to the Rust engine.

### Affected Parameters

| Parameter | UI Widget | Model Field | FFI Before | FFI After |
|-----------|-----------|-------------|------------|-----------|
| Fade In | Slider (0-2000ms) | `fadeInMs` | ❌ Not sent | ✅ Via extended FFI |
| Fade Out | Slider (0-2000ms) | `fadeOutMs` | ❌ Not sent | ✅ Via extended FFI |
| Trim Start | Slider (ms) | `trimStartMs` | ❌ Not sent | ✅ Via extended FFI |
| Trim End | Slider (ms) | `trimEndMs` | ❌ Not sent | ✅ Via extended FFI |
| Pan | Slider (-1 to +1) | `pan` | ❌ Not sent | ✅ Via extended FFI |
| Gain | Slider (0-2) | `gain` | ❌ Not sent | ✅ Via extended FFI |

### Root Cause

Original FFI function `middleware_add_action()` only accepted 9 parameters:
- event_id, action_type, asset_id, bus_id, scope
- priority, fade_curve, fade_time_ms, delay_ms

Extended playback parameters existed in Dart model (`MiddlewareAction`) but were never transmitted to Rust.

---

## Solution Architecture

### Layer-by-Layer Implementation

```
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 1: UI (event_editor_panel.dart)                               │
│ ├── _buildFadeInSlider() → action.fadeInMs                         │
│ ├── _buildFadeOutSlider() → action.fadeOutMs                       │
│ ├── _buildTrimStartSlider() → action.trimStartMs                   │
│ ├── _buildTrimEndSlider() → action.trimEndMs                       │
│ ├── _buildPanSlider() → action.pan                                 │
│ └── _buildGainSlider() → action.gain                               │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 2: Dart Model (middleware_models.dart)                        │
│ class MiddlewareAction {                                            │
│   double fadeInMs;    // 0.0 - 2000.0                              │
│   double fadeOutMs;   // 0.0 - 2000.0                              │
│   double trimStartMs; // 0.0 - duration                            │
│   double trimEndMs;   // 0.0 - duration                            │
│   double pan;         // -1.0 to +1.0                              │
│   double gain;        // 0.0 - 2.0                                 │
│ }                                                                   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 3: Provider (event_system_provider.dart)                      │
│ _addActionToEngine(int eventId, MiddlewareAction action) {          │
│   _ffi.middlewareAddActionEx(                                       │
│     eventId, actionType, assetId, busId, scope, priority,          │
│     fadeCurve, fadeTimeMs, delayMs,                                │
│     gain: action.gain,          // ← NEW                           │
│     pan: action.pan,            // ← NEW                           │
│     fadeInMs: action.fadeInMs,  // ← NEW                           │
│     fadeOutMs: action.fadeOutMs,// ← NEW                           │
│     trimStartMs: action.trimStartMs, // ← NEW                      │
│     trimEndMs: action.trimEndMs,     // ← NEW                      │
│   );                                                                │
│ }                                                                   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 4: Dart FFI Binding (native_ffi.dart)                         │
│ bool middlewareAddActionEx(                                         │
│   int eventId, MiddlewareActionType actionType,                    │
│   { int assetId, int busId, ... ,                                  │
│     double gain = 1.0,                                             │
│     double pan = 0.0,                                              │
│     int fadeInMs = 0,                                              │
│     int fadeOutMs = 0,                                             │
│     int trimStartMs = 0,                                           │
│     int trimEndMs = 0,                                             │
│   }                                                                 │
│ )                                                                   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 5: C FFI (middleware_ffi.rs)                                  │
│ #[unsafe(no_mangle)]                                                │
│ pub extern "C" fn middleware_add_action_ex(                         │
│   event_id: u32, action_type: u32, asset_id: u32, bus_id: u32,     │
│   scope: u32, priority: u32, fade_curve: u32,                      │
│   fade_time_ms: u32, delay_ms: u32,                                │
│   gain: f32, pan: f32,                    // ← EXTENDED            │
│   fade_in_ms: u32, fade_out_ms: u32,      // ← EXTENDED            │
│   trim_start_ms: u32, trim_end_ms: u32,   // ← EXTENDED            │
│ ) -> i32                                                            │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 6: Rust Model (action.rs)                                     │
│ pub struct MiddlewareAction {                                       │
│   // ... existing fields ...                                        │
│   pub pan: f32,            // -1.0 to +1.0                         │
│   pub fade_in_secs: f32,   // seconds                              │
│   pub fade_out_secs: f32,  // seconds                              │
│   pub trim_start_secs: f32, // seconds                             │
│   pub trim_end_secs: f32,   // seconds                             │
│ }                                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Files Modified

### Rust Layer

| File | Lines Changed | Description |
|------|---------------|-------------|
| `crates/rf-event/src/action.rs` | +15 | Added 5 fields to MiddlewareAction struct + Default impl |
| `crates/rf-bridge/src/middleware_ffi.rs` | +55 | Added `middleware_add_action_ex()` function |
| `crates/rf-engine/src/ffi.rs` | +5 | Updated MiddlewareAction init with extended field defaults |

### Dart Layer

| File | Lines Changed | Description |
|------|---------------|-------------|
| `flutter_ui/lib/src/rust/native_ffi.dart` | +40 | Added typedefs, late field, lookup, public method |
| `flutter_ui/lib/providers/subsystems/event_system_provider.dart` | +12 | Updated `_addActionToEngine()` to use extended FFI |

---

## Backward Compatibility

Original `middleware_add_action()` function preserved with default values for extended fields:

```rust
// Original function still works (defaults extended params)
pub extern "C" fn middleware_add_action(
    event_id: u32, action_type: u32, ..., delay_ms: u32,
) -> i32 {
    let action = MiddlewareAction {
        // ... basic fields ...
        // Extended fields default to neutral values:
        pan: 0.0,
        fade_in_secs: 0.0,
        fade_out_secs: 0.0,
        trim_start_secs: 0.0,
        trim_end_secs: 0.0,
    };
    // ...
}
```

---

## Parameter Conversion

| Dart (ms) | Rust (seconds) | Conversion |
|-----------|----------------|------------|
| `fadeInMs` | `fade_in_secs` | `fade_in_ms as f32 / 1000.0` |
| `fadeOutMs` | `fade_out_secs` | `fade_out_ms as f32 / 1000.0` |
| `trimStartMs` | `trim_start_secs` | `trim_start_ms as f32 / 1000.0` |
| `trimEndMs` | `trim_end_secs` | `trim_end_ms as f32 / 1000.0` |
| `pan` | `pan` | Direct (f32) |
| `gain` | `gain` | Direct (f32) |

---

## Comparison: SlotLab vs Middleware Audio Paths

| Feature | SlotLab | Middleware |
|---------|---------|------------|
| **Trigger Method** | EventRegistry.triggerStage() | MiddlewareProvider.postEvent() |
| **Model** | AudioLayer | MiddlewareAction |
| **FFI Function** | `playFileToBusEx()` | `middlewareAddActionEx()` |
| **Fade In/Out** | ✅ AudioLayer.fadeInMs/fadeOutMs | ✅ MiddlewareAction.fadeInMs/fadeOutMs |
| **Trim** | ✅ AudioLayer.trimStartMs/trimEndMs | ✅ MiddlewareAction.trimStartMs/trimEndMs |
| **Pan** | ✅ AudioLayer.pan | ✅ MiddlewareAction.pan |
| **Gain** | ✅ AudioLayer.volume | ✅ MiddlewareAction.gain |

**Key Insight:** Both systems now have full extended playback parameter support, but use DIFFERENT FFI paths.

---

## Testing Checklist

1. [ ] Open Middleware section
2. [ ] Create new event with Play action
3. [ ] Set fade in to 500ms
4. [ ] Set fade out to 1000ms
5. [ ] Set trim start to 100ms
6. [ ] Set trim end to 2000ms
7. [ ] Set pan to -0.5 (left)
8. [ ] Set gain to 1.5
9. [ ] Play event via postEvent()
10. [ ] Verify audio:
    - [ ] Fades in over 500ms
    - [ ] Starts at 100ms into file
    - [ ] Ends at 2000ms into file
    - [ ] Panned to left speaker
    - [ ] Louder than original

---

## Related Documentation

- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Updated with Middleware FFI Extended Chain section
- `.claude/architecture/MIDDLEWARE_DECOMPOSITION.md` — Updated EventSystemProvider FFI info
- `CLAUDE.md` — P0.6 section added
- `.claude/analysis/MIDDLEWARE_INSPECTOR_PAN_FIX_2026_01_25.md` — Related pan slider race condition fix

---

**Last Updated:** 2026-01-26
