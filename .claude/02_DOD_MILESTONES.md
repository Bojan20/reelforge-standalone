# FluxForge Studio — Definition of Done (Milestones)

These are production gates. "Works" is not "Done".

**Last Updated:** 2026-01-21

---

## ✅ COMPLETE — SlotLab Timeline Layer Drag (2026-01-21)

Exit Criteria:

- ✅ Layer drag works on first attempt
- ✅ Layer drag works on second+ attempt (no position jump)
- ✅ Event log shows one entry per stage (no duplicates)
- ✅ Stages without audio show warning icon
- ✅ No lag during drag operations

Root Cause Fixed:

- **Problem:** Layer jumped to timeline start on second drag
- **Cause:** Relative offset calculation used stale `region.start` value
- **Solution:** Switched to absolute positioning - read `offsetMs` directly from provider

Key Changes:

| Component | Change |
|-----------|--------|
| TimelineDragController | Stores `_absoluteStartSeconds` instead of relative offset |
| onHorizontalDragStart | Reads `offsetMs` from provider, converts to seconds |
| getAbsolutePosition() | Returns `_absoluteStartSeconds + _layerDragDelta` |
| Visual position | Computed as `absolutePosition - region.start` |

Files Changed:

- `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart` — Absolute positioning
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Fresh values from provider
- `flutter_ui/lib/services/event_registry.dart` — triggerStage notifies for all stages
- `flutter_ui/lib/widgets/slot_lab/event_log_panel.dart` — Deduplication

Commits:

| Hash | Description |
|------|-------------|
| `e1820b0c` | Event log deduplication + captured values pattern |
| `97d8723f` | Absolute positioning za layer drag |
| `832554c6` | Documentation update |

---

## ✅ COMPLETE — FabFilter-Style DSP Panels (2026-01-20)

Exit Criteria:

- ✅ Pro-Q style EQ panel with 64-band interactive spectrum
- ✅ Pro-C style Compressor panel with knee visualization
- ✅ Pro-L style Limiter panel with LUFS metering
- ✅ Pro-R style Reverb panel with decay display
- ✅ Pro-G style Gate panel with threshold visualization
- ✅ All panels connected to Rust FFI
- ✅ A/B comparison support
- ✅ Undo/Redo support
- ✅ Preset browser integration
- ✅ Lower Zone tab integration (Process group)

Performance:

- ✅ Real-time metering (60fps)
- ✅ No allocations in audio callback
- ✅ FFI parameter updates lock-free

Files:

- `flutter_ui/lib/widgets/fabfilter/` — 10 files, ~6,400 LOC

---

## ✅ COMPLETE — Lower Zone Tab System (2026-01-20)

Exit Criteria:

- ✅ 47 tabs across 7 groups
- ✅ All tabs have matching LowerZoneTab definitions
- ✅ All tabs properly assigned to groups
- ✅ Editor mode filtering (DAW/Middleware)
- ✅ Tab persistence per mode

Issues Fixed:

- ✅ `event-editor` tab definition missing → ADDED
- ✅ 5 FabFilter tabs orphaned → ADDED to process group

Statistics:

- 47 total tabs
- 46 functional (1 placeholder: audio-browser)
- 7 groups: timeline, editing, process, analysis, mix, middleware, slot-lab

---

## ✅ COMPLETE — P0 Critical Fixes (2026-01-20)

Exit Criteria:

- ✅ P0.1: Sample rate hardcoding fixed (engine.rs)
- ✅ P0.2: Heap allocation marked cold (dual_path.rs from_slices)
- ✅ P0.3: RwLock replaced with lock-free atomics (param_smoother.rs)
- ✅ P0.4: log::warn!() removed from audio callback (playback.rs)
- ✅ P0.5: Null checks verified in FFI C exports
- ✅ P0.6: Bounds validation added (native_ffi.dart)
- ✅ P0.7: Race condition fixed with CAS (slot_lab_ffi.rs)
- ✅ P0.8: PDC integrated in routing (routing.rs Channel::process)
- ✅ P0.9: Send tap points implemented (PreFader/PostFader/PostPan)
- ✅ P0.10: shouldRepaint guards added to CustomPainters

Key Changes:

| Fix | File | Solution |
|-----|------|----------|
| Lock-free params | param_smoother.rs | AtomicU64 + pre-allocated 256-slot array |
| PDC routing | routing.rs | ChannelPdcBuffer + recalculate_pdc() |
| Send tap points | routing.rs | prefader/postfader/output buffers per channel |
| Race-free init | slot_lab_ffi.rs | AtomicU8 state machine with CAS |

Performance:

- ✅ Zero allocations in audio callback
- ✅ Zero locks in real-time path
- ✅ Zero syscalls in audio thread
- ✅ Phase-coherent routing with PDC

Files Changed:

- `crates/rf-engine/src/param_smoother.rs` — Complete rewrite (~320 LOC)
- `crates/rf-engine/src/routing.rs` — PDC + tap points (~200 LOC added)
- `crates/rf-engine/src/playback.rs` — Removed log calls
- `crates/rf-engine/src/dual_path.rs` — Marked allocating fn cold
- `crates/rf-bridge/src/slot_lab_ffi.rs` — CAS state machine
- `flutter_ui/lib/src/rust/native_ffi.dart` — Bounds validation
- 6 Flutter CustomPainter files — shouldRepaint guards

---

## ✅ COMPLETE — Slot Lab Audio P0 Fixes (2026-01-20)

Exit Criteria:

- ✅ P0.1: Audio latency calibration with profile-based timing (timing.rs)
- ✅ P0.2: Seamless REEL_SPIN loop with position wrapping (playback.rs)
- ✅ P0.3: Per-voice pan with equal-power panning (playback.rs:672-721)
- ✅ P0.4: Dynamic cascade timing via RTPC (slot_lab_provider.dart)
- ✅ P0.5: Dynamic rollup speed via RTPC (slot_lab_provider.dart)
- ✅ P0.6: Anticipation pre-trigger with lookahead timer (slot_lab_provider.dart)
- ✅ P0.7: Big Win layered audio templates (event_registry.dart)

Key Changes:

| Fix | File | Solution |
|-----|------|----------|
| Latency calibration | timing.rs | Profile-based offsets (Normal=5ms, Studio=3ms) |
| Seamless loop | playback.rs | `looping` flag + position wrapping |
| Per-voice pan | playback.rs | Equal-power panning formula |
| Pre-trigger | slot_lab_provider.dart | Separate `_audioPreTriggerTimer` |
| Big Win layers | event_registry.dart | 4-layer templates per tier |

Performance:

- ✅ Audio-visual sync: ±3-5ms (was ±15-20ms)
- ✅ REEL_SPIN loop: Seamless (was audible clicks)
- ✅ Spatial audio: Applied (was ignored)

Additional P1 Features Implemented:

- ✅ P1.1: Symbol-specific audio (WILD, SCATTER, SEVEN)
- ✅ P1.2: Near miss audio escalation (intensity-based)
- ✅ P1.3: Win line panning (position-based)

Files Changed:

- `crates/rf-engine/src/playback.rs` — Loop + pan implementation
- `crates/rf-slot-lab/src/timing.rs` — Latency config fields
- `flutter_ui/lib/providers/slot_lab_provider.dart` — Pre-triggers, RTPC
- `flutter_ui/lib/services/event_registry.dart` — Big win templates

Documentation:

- `.claude/implementation/SLOT_LAB_P0_AUDIO_FIXES.md`
- `.claude/architecture/SLOT_LAB_SYSTEM.md` (updated)

---

## P1 — Plugin Hosting

Exit Criteria:

- Each channel supports up to 8 inserts
- Zero-copy processing
- Automatic PDC
- Per-slot:
  - bypass
  - wet/dry mix
- No allocations in audio thread
- FFI exposes:
  - load/remove
  - bypass
  - mix
  - latency query
- UI can:
  - add/remove plugins
  - toggle bypass
  - adjust mix

Performance:

- < 0.1% CPU overhead per 8-slot chain
- No glitch on enable/disable

Failure Conditions:

- Allocations in process()
- UI blocking on plugin scan
- PDC drift
- Audio thread locks

---

## P1 — Recording System

Exit Criteria:

- Arm per track
- Record to disk in real time
- No dropouts at 48kHz / 256 buffer
- UI feedback per armed track
- File naming deterministic

Performance:

- Disk I/O on worker thread
- Zero blocking in audio thread

Failure Conditions:

- Audio callback blocked by disk
- Frame drops during recording
- Non-deterministic file output

---

## P1 — Export / Render

Exit Criteria:

- Offline render
- Faster-than-realtime
- Bit-exact with realtime path
- Supports:
  - master
  - stems
- Deterministic output

Failure Conditions:

- Realtime-only path
- Drift vs live playback
- Non-repeatable exports

---

## P2 — SlotLab Timeline UX Polish

### P2.1 — Snap-to-Grid

Exit Criteria:

- Grid intervals: 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- Toggle via keyboard (G) or toolbar button
- Visual grid lines when snap enabled
- Layer snaps to nearest grid point on release

Implementation:

- `TimelineDragController._snapToGrid(position, interval)`
- Grid interval dropdown in toolbar
- Grid lines overlay widget

Files:

- `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart`
- `flutter_ui/lib/screens/slot_lab_screen.dart`
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart` (new)

---

### P2.2 — Timeline Zoom

Exit Criteria:

- Zoom levels: 0.5x, 1x, 2x, 4x, 8x, 16x
- Controls: Mouse wheel + Ctrl, +/- keys, slider
- Zoom centers on cursor position
- Smooth zoom animation

Implementation:

- `_zoomLevel` state in slot_lab_screen.dart
- `_pixelsPerSecond = 100.0 * _zoomLevel`
- Zoom slider in toolbar

Files:

- `flutter_ui/lib/screens/slot_lab_screen.dart`
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart`

---

### P2.3 — Drag Waveform Preview

Exit Criteria:

- Ghost outline at original position during drag
- Semi-transparent waveform at current position
- Time tooltip showing position in ms

Implementation:

- Stack with ghost + dragging layer
- Positioned tooltip above layer

Files:

- `flutter_ui/lib/screens/slot_lab_screen.dart` (_buildDraggableLayerRow)

---

## P2 — SlotLab Audio Preview

### P2.4 — Hover Audio Preview

Exit Criteria:

- 500ms hover delay before playback
- Play first 3 seconds of audio
- Stop on mouse leave
- Respects preview volume setting

Implementation:

- `AudioHoverPreview` widget with Timer
- `AudioPlaybackService.playPreview()` method

Files:

- `flutter_ui/lib/widgets/slot_lab/audio_hover_preview.dart`
- `flutter_ui/lib/services/audio_playback_service.dart`

---

### P2.5 — Waveform Thumbnails

Exit Criteria:

- 80x24px mini waveform in file browser
- Cached by file path
- Async generation with placeholder
- Rust FFI for fast generation

Implementation:

- `WaveformThumbnailCache` singleton
- `NativeFFI.generateWaveformThumbnail()` FFI call

Files:

- `flutter_ui/lib/services/waveform_thumbnail_cache.dart` (new)
- `crates/rf-bridge/src/waveform_ffi.rs` (new)

---

## P2 — SlotLab Event Editor

### P2.6 — Multi-Select Layers

Exit Criteria:

- Ctrl+click toggles selection
- Shift+click selects range
- Visual highlight on selected
- Bulk delete/move/copy operations

Implementation:

- `Set<String> _selectedLayerIds` state
- `_handleLayerClick()` with modifier detection

Files:

- `flutter_ui/lib/screens/slot_lab_screen.dart`

---

### P2.7 — Copy/Paste Layers

Exit Criteria:

- Ctrl+C copies selected layers
- Ctrl+V pastes into current event
- New IDs generated for pasted layers
- Preserves all layer properties

Implementation:

- `LayerClipboard` singleton
- Keyboard shortcuts in slot_lab_screen

Files:

- `flutter_ui/lib/services/layer_clipboard.dart` (new)
- `flutter_ui/lib/screens/slot_lab_screen.dart`

---

### P2.8 — Fade Controls

Exit Criteria:

- Fade In: 0-5000ms slider
- Fade Out: 0-5000ms slider
- Visual curve overlay on waveform
- Applied during playback

Implementation:

- Sliders in layer detail panel
- Fade curve painter widget
- Apply in AudioPlaybackService

Files:

- `flutter_ui/lib/screens/slot_lab_screen.dart`
- `flutter_ui/lib/widgets/slot_lab/fade_curve_overlay.dart` (new)

---

## P3 — Middleware Integration

### P3.1 — RTPC Visualization

Exit Criteria:

- Sparkline graphs for each RTPC
- 60fps update during spin
- 5-second history buffer
- Numeric current value display

Files:

- `flutter_ui/lib/widgets/middleware/rtpc_monitor_widget.dart` (new)

---

### P3.2 — Ducking Matrix UI

Exit Criteria:

- Grid matrix (sources × targets)
- Per-cell: amount, attack, release
- Color intensity = ducking amount
- Real-time highlight during playback

Files:

- `flutter_ui/lib/widgets/middleware/ducking_matrix_panel.dart`

---

### P3.3 — ALE Integration

Exit Criteria:

- Spin results → ALE signals (winTier, winXbet, etc.)
- Auto context switch (BASE → FREESPINS → BIGWIN)
- Real-time layer volume bars
- Profile editor in SlotLab

Files:

- `flutter_ui/lib/providers/ale_provider.dart`
- `flutter_ui/lib/providers/slot_lab_provider.dart`
- `flutter_ui/lib/widgets/ale/`

---

## P4 — Production Export

### P4.1 — Event Export

Exit Criteria:

- JSON format for web/Unity
- XML format for Wwise compatibility
- Includes: events, buses, RTPCs, ducking rules

Files:

- `flutter_ui/lib/services/event_export_service.dart` (new)

---

### P4.2 — Audio Pack Export

Exit Criteria:

- WAV 48kHz/24bit, MP3, OGG formats
- Apply volume, pan, fades in render
- Configurable naming convention
- Flat or folder-per-event structure

Files:

- `flutter_ui/lib/services/audio_pack_export_service.dart` (new)
- `crates/rf-bridge/src/export_ffi.rs` (new)
