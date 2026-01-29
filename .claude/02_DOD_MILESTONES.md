# FluxForge Studio — Definition of Done (Milestones)

These are production gates. "Works" is not "Done".

**Last Updated:** 2026-01-29

---

## ✅ COMPLETE — DAW Lower Zone P0+P1+P2 (2026-01-29)

**Tracking Document:** `.claude/tasks/DAW_LOWER_ZONE_TODO_2026_01_26.md`

Exit Criteria:

- ✅ Input validation utility (path traversal prevention)
- ✅ FFI bounds checking (NaN/Infinite protection)
- ✅ Error boundary pattern (graceful degradation)
- ✅ Real-time LUFS metering (streaming compliance)
- ✅ FX chain parameter preservation (no data loss on reorder)
- ✅ Provider access pattern standard (code consistency)
- ✅ Command Palette (Cmd+K) with 16 DAW commands
- ✅ DAW workspace presets (4 built-in)
- ✅ Dead code cleanup (62% file size reduction)

Key Changes:

| Component | Change | LOC |
|-----------|--------|-----|
| Input Validation | PathValidator, InputSanitizer, FFIBoundsChecker | +350 |
| Error Boundary | ErrorBoundary, ErrorPanel, ProviderErrorBoundary | +280 |
| LUFS Metering | LufsMeterWidget, LufsBadge, CompactLufsDisplay | +430 |
| Parameter Restoration | DspChainProvider._restoreNodeParameters() | +100 |
| Provider Pattern Guide | PROVIDER_ACCESS_PATTERN.md | +450 |
| Command Palette | command_palette.dart, FluxForgeCommands | +436 |
| Dead Code Cleanup | Removed duplicates in daw_lower_zone_widget | -1,654 |
| **NET TOTAL** | | **+392** |

Files Created:

- `flutter_ui/lib/utils/input_validator.dart` — Security validation
- `flutter_ui/lib/widgets/common/error_boundary.dart` — Error handling
- `flutter_ui/lib/widgets/meters/lufs_meter_widget.dart` — LUFS metering
- `flutter_ui/lib/widgets/mixer/lufs_display_compact.dart` — Compact LUFS
- `flutter_ui/lib/widgets/common/command_palette.dart` — VS Code-style command palette
- `.claude/guides/PROVIDER_ACCESS_PATTERN.md` — Code standard

Files Modified:

- `flutter_ui/lib/providers/dsp_chain_provider.dart` — Parameter restoration
- `flutter_ui/lib/providers/mixer_provider.dart` — Input validation + FFI bounds
- `flutter_ui/lib/widgets/lower_zone/daw_lower_zone_widget.dart` — Validation + LUFS + Error boundary + cleanup (5,540→2,089 LOC)
- `flutter_ui/lib/screens/main_layout.dart` — Cmd+K shortcut handler
- `flutter_ui/lib/models/layout_models.dart` — MenuCallbacks extensions

Verification:

- ✅ `flutter analyze` passes (0 errors)
- ✅ Security: Path validation, input sanitization, FFI bounds
- ✅ Stability: Error boundaries, parameter preservation
- ✅ Professional: LUFS metering for streaming compliance
- ✅ 165 tests passing

P0 Tasks — ALL COMPLETE (2026-01-29):

- ✅ P0.1: File Split — 100% (20/20 panels, **2,089 LOC** after cleanup)
- ✅ P0.2: LUFS Metering — 100%
- ✅ P0.3: Input Validation — 100%
- ✅ P0.4: Unit Tests — 100% (**165 tests** passing)
- ✅ P0.5: Timeline↔Mixer Sync — 100%
- ✅ P0.6: Plugin FFI — 100%
- ✅ P0.7: Channel Strip DSP — 100%
- ✅ P0.8: Tempo Sync — 100%

P1 Tasks — ALL COMPLETE (2026-01-29):

- ✅ P1.1: DAW Workspace Presets — 4 built-in presets
- ✅ P1.2: Command Palette — Cmd+K with 16 commands
- ✅ P1.3: PDC Indicator — Visual latency display
- ✅ P1.4: Master Pan Law — FFI connected
- ✅ P1.5: Quick Export Format — WAV/FLAC/MP3
- ✅ P1.6: Track Templates — Preset loading

P2 Tasks — ALL COMPLETE (2026-01-29):

- ✅ P2.1: Split View Mode — Already implemented
- ✅ P2.2: GPU Spectrum Shader — Already implemented
- ✅ P2.3: Multiband Compressor — Already implemented
- ✅ P2.4: Correlation Meter — Already implemented
- ✅ P2.5: Track Notes Panel — NEW (~380 LOC)
- ✅ P2.6: Marker Timeline — Already implemented
- ✅ P2.7: A/B Compare for DSP — Already implemented
- ✅ P2.8: Parameter Lock — NEW (~400 LOC)
- ✅ P2.9: Undo History Panel — Already implemented
- ✅ P2.10: Mastering Preset Manager — Already implemented
- ✅ P2.11: Channel Strip Presets — NEW (~650 LOC)
- ✅ P2.12: Keyboard Shortcut Editor — Already implemented
- ✅ P2.13: Touch/Pen Mode — NEW (~540 LOC)
- ✅ P2.14: Dark/Light Theme Toggle — Already implemented
- ✅ P2.15: Panel Opacity Control — NEW (~380 LOC)
- ✅ P2.16: Auto-Hide Mode — NEW (~520 LOC)
- ✅ P2.17: Export Settings Panel — Already implemented

P3 Tasks — ✅ COMPLETE (7/7):

| # | Task | Effort | Status |
|---|------|--------|--------|
| **P3.1** | Audio Settings Panel | 2 days | ✅ DONE |
| **P3.2** | CPU Usage Meter per Processor | 2 days | ✅ DONE |
| **P3.3** | Spectrum Waterfall Display | 3 days | ✅ DONE |
| **P3.4** | Track Color Customization | 2 days | ✅ DONE |
| **P3.5** | Mini Mixer View | 2 days | ✅ DONE |
| **P3.6** | Session Notes Panel | 1 day | ✅ DONE |
| **P3.7** | Export Preset Manager | 2 days | ✅ DONE |

P3.1 Audio Settings Panel: ✅ DONE
- Sample rate selector (44.1/48/88.2/96/176.4/192 kHz)
- Buffer size selector (32-4096 samples)
- Audio device selection dropdown
- Visual latency indicator (ms display)
- Test tone generator button
- File: `daw_lower_zone_widget.dart`

P3.2 CPU Usage Meter per Processor: ✅ DONE
- Per-processor CPU estimation model based on type
- Estimation factors: EQ=1.5, Compressor=2.0, Limiter=2.5, Reverb=4.0, etc.
- ProcessorCpuMeterInline widget (70×6px inline bar)
- ProcessorCpuBadge widget (track total with percentage)
- Color coding: Green (<50%), Yellow (50-80%), Red (>80%)
- Files: `processor_cpu_meter.dart` (~480 LOC), `fx_chain_panel.dart`

P3.3 Spectrum Waterfall Display: ✅ DONE
- Scrolling waterfall/spectrogram view (newest at bottom)
- Display modes: Waterfall, Spectrogram
- Color gradients: Heat, Ice, Magma, Viridis, Mono
- History length: 1s, 2s, 3s, 5s, 10s options
- FFT size: 1024-8192 configurable
- File: `spectrum_waterfall_panel.dart` (~500 LOC)

P3.4 Track Color Customization: ✅ DONE
- 16 preset colors (DAW industry standard palette)
- Custom HSL color picker with sliders
- Right-click popup menu integration
- TrackColorIndicator widget for track headers
- Extension method: `.withTrackColorPicker()` for easy integration
- File: `track_color_picker.dart` (~480 LOC)

P3.5 Mini Mixer View: ✅ DONE
- Condensed 40px channel strips (vs 80px normal)
- Fader + peak meter + M/S buttons only
- dB value display per channel
- Unity gain marker on faders
- Master bus with separator
- File: `mini_mixer_panel.dart` (~460 LOC)

P3.6 Session Notes Panel: ✅ DONE
- Rich text with bold/italic/bullet/numbered lists
- Auto-save with 2s debounce
- Word/character count in status bar
- Timestamp insertion, separator line
- Clear notes with confirmation dialog
- File: `session_notes_panel.dart` (~500 LOC)

P3.7 Export Preset Manager: ✅ DONE
- 5 built-in presets: Streaming, Broadcast, Archive, Stems, MP3 Web
- Custom preset CRUD with save/duplicate/delete
- Format options: WAV 16/24/32f, FLAC, MP3 (High/Med/Low), OGG, AAC
- Normalization: None, Peak, LUFS Integrated/Streaming/Broadcast
- True Peak limiting with dBTP ceiling
- Stems modes: All Tracks, Selected, By Bus, By Group
- Dithering: None, TPDF, Noise Shaped, POW-r
- File: `export_preset_manager.dart` (~950 LOC)

**Remaining Effort:** 0 days — DAW Lower Zone Complete!

**Status:** P0 ✅ 8/8, P1 ✅ 6/6, P2 ✅ 17/17, P3 ✅ 7/7 (100%)

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

## ✅ COMPLETE — System Review Fixes (2026-01-21)

Four tasks from system weakness review all resolved.

### W1: MiddlewareProvider Decomposition Phase 3

Exit Criteria:
- ✅ BlendContainersProvider extracted (~350 LOC)
- ✅ RandomContainersProvider extracted (~300 LOC)
- ✅ SequenceContainersProvider extracted (~400 LOC)
- ✅ GetIt registration for all 3 providers
- ✅ MiddlewareProvider delegation methods

### W2: api.rs Module Splitting

Exit Criteria:
- ✅ api_engine.rs created (~60 LOC)
- ✅ api_transport.rs created (~100 LOC)
- ✅ api_metering.rs created (~70 LOC)
- ✅ api_mixer.rs created (~130 LOC)
- ✅ api_project.rs created (~540 LOC)
- ✅ api.rs reduced from 6594 to 5695 LOC
- ✅ All re-exports working

### W4: Sprint 2 unwrap() Fixes

Exit Criteria:
- ✅ command_queue.rs: `.unwrap()` → `.expect()` with SAFETY comments
- ✅ automation.rs: Extracted to named variables with safety invariants
- ✅ export.rs: Extracted to named variables with safety invariants
- ✅ cargo build passes
- ✅ No new clippy warnings

### W5: Compressor/Limiter InsertChain Integration

Exit Criteria:
- ✅ ALREADY IMPLEMENTED via existing FFI
- ✅ `ensure_compressor_loaded()` auto-loads CompressorWrapper at slot 1
- ✅ `ensure_limiter_loaded()` auto-loads TruePeakLimiterWrapper at slot 2
- ✅ 14 FFI functions expose all parameters
- ✅ Flutter bindings in native_ffi.dart

Files Changed:
- `crates/rf-bridge/src/api_*.rs` — 5 new module files
- `crates/rf-bridge/src/lib.rs` — Module registration
- `crates/rf-bridge/src/command_queue.rs` — Safety fixes
- `crates/rf-engine/src/automation.rs` — Safety fixes
- `crates/rf-engine/src/export.rs` — Safety fixes
- `flutter_ui/lib/providers/subsystems/*_provider.dart` — 3 new container providers
- `flutter_ui/lib/services/service_locator.dart` — GetIt registrations

Documentation:
- `.claude/architecture/SYSTEM_REVIEW_FIXES_2026_01_21.md` (comprehensive)
- `.claude/architecture/MIDDLEWARE_DECOMPOSITION.md` (updated)

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

## ✅ COMPLETE — P2.1 Snap-to-Grid (2026-01-21)

Exit Criteria:

- ✅ Grid intervals: 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- ✅ Toggle via keyboard (S) or toolbar button
- ✅ Visual grid lines when snap enabled
- ✅ Layer snaps to nearest grid point on release
- ✅ Region snaps to nearest grid point on release

Key Changes:

| Component | Change |
|-----------|--------|
| TimelineDragController | Added `GridInterval` enum, `snapToGrid()`, `toggleSnap()`, `setGridInterval()` |
| endLayerDrag() | Now uses `getSnappedAbsolutePosition()` |
| endRegionDrag() | Now uses `snapToGrid()` for snapped position |
| TimelineToolbar | Snap toggle button + interval dropdown |
| TimelineGridOverlay | Visual grid lines at snap intervals |
| Keyboard | S key toggles snap on/off |

Files Changed:

- `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart` — Snap logic
- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart` — New toolbar widget
- `flutter_ui/lib/widgets/slot_lab/timeline_grid_overlay.dart` — New grid overlay widget
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Integration + S keyboard shortcut

---

## ✅ COMPLETE — P2.2 Timeline Zoom (2026-01-21)

Exit Criteria:

- ✅ Zoom levels: 0.1x - 10x continuous range
- ✅ Controls: Mouse wheel + Ctrl, G/H keys, slider in toolbar
- ✅ Zoom reset: Ctrl+0 or click percentage
- ✅ Visual feedback: Percentage display in toolbar

Key Changes:

| Component | Change |
|-----------|--------|
| TimelineToolbar | Added _ZoomControls with slider, +/- buttons, percentage display |
| _buildTimelineContent | Added Listener for Ctrl+scroll wheel zoom |
| Keyboard | G = zoom out, H = zoom in, Ctrl+0 = reset to 100% |

Files Changed:

- `flutter_ui/lib/widgets/slot_lab/timeline_toolbar.dart` — Zoom controls
- `flutter_ui/lib/screens/slot_lab_screen.dart` — Mouse wheel zoom integration

Note: Cursor-centered zoom deferred - current implementation zooms around left edge.

---

## ✅ COMPLETE — P2.3 Drag Waveform Preview (2026-01-21)

Exit Criteria:

- ✅ Ghost outline at original position during drag
- ✅ Semi-transparent waveform at current position (via opacity)
- ✅ Time tooltip showing position in ms

Key Changes:

| Component | Change |
|-----------|--------|
| _buildDraggableLayerRow | Added ghost outline Positioned widget |
| _buildDraggableLayerRow | Added time tooltip above layer during drag |
| _formatTimeMs | New helper for tooltip display (ms, s, m:s formats) |

Files Changed:

- `flutter_ui/lib/screens/slot_lab_screen.dart` — Ghost outline, tooltip, helper

---

## P2 — SlotLab Timeline UX Polish

---

## P2 — SlotLab Audio Preview

### P2.4 — Audio Preview (Manual Play/Stop)

> **V6.4 Update (2026-01-26):** Hover auto-play DISABLED. Now uses manual play/stop buttons.

Exit Criteria:

- ~~500ms hover delay before playback~~ **DISABLED**
- Manual play/stop buttons (visible on hover or while playing)
- Playback continues until manually stopped
- Respects preview volume setting

Implementation:

- `_HoverPreviewItem` widget with play/stop buttons
- `AudioPlaybackService.previewFile()` method

Files:

- `flutter_ui/lib/widgets/slot_lab/events_panel_widget.dart`
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
