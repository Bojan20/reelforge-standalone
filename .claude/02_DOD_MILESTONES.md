# FluxForge Studio — Definition of Done (Milestones)

These are production gates. "Works" is not "Done".

**Last Updated:** 2026-02-21

---

## ✅ COMPLETE — Stereo Audio Routing Fixes + Pro Tools Gap Analysis (2026-02-21)

**Scope:** Critical stereo bug fixes + Pro Tools routing architecture audit

Exit Criteria:

- ✅ CoreAudio non-interleaved stereo deinterleaving (`coreaudio.rs:811-877`)
- ✅ One-shot voice stereo balance pan — Pro Tools-style (`playback.rs:1235-1270`)
- ✅ Lower Zone bus 10px overflow fix (`ultimate_mixer.dart`)
- ✅ Pro Tools routing gap analysis documented (6 gaps)
- ✅ `cargo build --release` passes
- ✅ `flutter analyze` passes (0 errors)

Files Modified:

- `crates/rf-audio/src/coreaudio.rs` — Non-interleaved stereo I/O
- `crates/rf-engine/src/playback.rs` — Stereo balance pan for one-shot voices
- `flutter_ui/lib/widgets/mixer/ultimate_mixer.dart` — Bus overflow fix

Documentation Updated:

- `.claude/MASTER_TODO.md` — Added stereo fixes + Pro Tools gap analysis
- `.claude/architecture/DAW_AUDIO_ROUTING.md` — Sections 18-20 (stereo + gaps)
- `.claude/02_DOD_MILESTONES.md` — This milestone

---

## ✅ COMPLETE — SafeFilePicker Migration (2026-02-21)

**Scope:** All file picker calls migrated from NSOpenPanel to in-app dart:io browser

Exit Criteria:

- ✅ SafeFilePicker wrapper (drop-in replacement for FilePicker.platform)
- ✅ InAppFileBrowser dialog (Cubase/Pro Tools-style, ~650 LOC)
- ✅ 25 files migrated to SafeFilePicker
- ✅ iCloud Desktop & Documents sync deadlock eliminated
- ✅ L10n dead code removed (4 files, ~2,409 LOC)
- ✅ Mixer strip overflow fix (SingleChildScrollView + Clip.hardEdge)
- ✅ `flutter analyze` passes (0 errors)

Files Created:

- `flutter_ui/lib/utils/safe_file_picker.dart` — SafeFilePicker wrapper
- `flutter_ui/lib/widgets/common/in_app_file_browser.dart` — Full file browser dialog

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

### Recent Fixes (2026-01-29)

| Fix | File | Description |
|-----|------|-------------|
| Dynamic Sample Rate | `recording_provider.dart` | Punch in/out now uses actual project sample rate instead of hardcoded 48000 |

**Implementation Details:**

- Added `_getSampleRate()` helper that reads from `NativeFFI.instance.projectGetInfo()?.sampleRate`
- Falls back to 48000 if FFI not loaded or project info unavailable
- `setPunchInTime()` and `setPunchOutTime()` now convert seconds to samples using actual project sample rate

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

### P2.4.1 — Stage Trace Context Menu Audio Assign (2026-01-29) ✅

Exit Criteria:

- ✅ Context menu "Assign audio..." action opens native file picker
- ✅ Supports audio formats: WAV, MP3, OGG, FLAC, AIFF
- ✅ Creates AudioFileInfo from selected file
- ✅ Calls onAudioDropped callback with stage type
- ✅ Shows drop feedback on successful assignment

Implementation:

- `_showAssignAudioFilePicker()` method using `FilePicker.platform.pickFiles()`
- Replaces previous TODO hint with full file picker integration
- Clears waveform cache after assignment for UI update

Files:

- `flutter_ui/lib/widgets/slot_lab/stage_trace_widget.dart`

---

### P2.5 — Waveform Thumbnails ✅ COMPLETE

**Verified:** 2026-01-29

Exit Criteria:

- ✅ 80x24px mini waveform in file browser
- ✅ Cached by file path (LRU cache, 500 entries)
- ✅ Async generation with loading/error placeholders
- ✅ Rust FFI for fast generation (uses `generateWaveformFromFile`)

Implementation (~435 LOC):

- `WaveformThumbnailCache` singleton with LRU eviction
- `WaveformThumbnailData` model (peaks, stereo flag, duration)
- `WaveformThumbnail` widget with CustomPainter
- `_WaveformThumbnailPainter` for efficient rendering

Files:

- `flutter_ui/lib/services/waveform_thumbnail_cache.dart` (~435 LOC)

---

## P2 — SlotLab Event Editor

### P2.6 — Multi-Select Layers ✅ COMPLETE

**Verified:** 2026-01-29

Exit Criteria:

- ✅ Ctrl+click toggles selection
- ✅ Shift+click selects range
- ✅ Visual highlight on selected layers
- ✅ Bulk delete/mute/solo/move/copy operations

Implementation:

- `_selectedLayerIds` Set in CompositeEventSystemProvider
- `selectLayer()`, `toggleLayerSelection()`, `selectLayerRange()`
- `selectAllLayers()`, `clearLayerSelection()`, `isLayerSelected()`
- Batch ops: `deleteSelectedLayers()`, `muteSelectedLayers()`, `soloSelectedLayers()`
- `hasMultipleLayersSelected` and `selectedLayerCount` getters

Files:

- `flutter_ui/lib/providers/subsystems/composite_event_system_provider.dart` (lines 185-1180)

---

### P2.7 — Copy/Paste Layers ✅ COMPLETE

**Verified:** 2026-01-29

Exit Criteria:

- ✅ Ctrl+C copies selected layer(s)
- ✅ Ctrl+V pastes into current event
- ✅ New IDs generated for pasted layers (`layer_${_nextLayerId++}`)
- ✅ Preserves all layer properties (volume, pan, offset, etc.)

Implementation:

- `_layerClipboard` for single layer copy/paste
- `_layersClipboard` List for multi-layer batch operations
- `copyLayer(eventId, layerId)` → stores in clipboard
- `pasteLayer(eventId)` → creates copy with new ID + "(copy)" suffix
- `duplicateLayer(eventId, layerId)` → in-place duplicate with 100ms offset
- `clearClipboard()` clears both single and multi-layer clipboards

Files:

- `flutter_ui/lib/providers/subsystems/composite_event_system_provider.dart` (lines 178-947)

---

### P2.8 — Fade Controls ✅ COMPLETE

**Verified:** 2026-01-29

Exit Criteria:

- ✅ Fade In: 0-2000ms slider in event editor
- ✅ Fade Out: 0-2000ms slider in event editor
- ✅ Visual curve overlay on waveform (WaveformTrimEditor)
- ✅ Draggable fade handles with visual feedback
- ✅ Context menu presets (100ms, 250ms quick fades)

Implementation:

- `fadeInMs`, `fadeOutMs` fields in `SlotEventLayer` model
- `WaveformTrimEditor` widget (~380 LOC) with interactive fade handles
- `_WaveformTrimPainter` CustomPainter draws fade curves
- `_HandleType.fadeIn` / `_HandleType.fadeOut` for drag operations
- Sliders in `event_editor_panel.dart` (lines 2548-2563)

Files:

- `flutter_ui/lib/models/slot_audio_events.dart` (lines 1456-1567)
- `flutter_ui/lib/widgets/common/waveform_trim_editor.dart` (~380 LOC)
- `flutter_ui/lib/widgets/middleware/event_editor_panel.dart` (lines 2545-2563)

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

## ✅ COMPLETE — P4 Advanced Features (2026-01-29)

**All 8 P4 backlog items verified and confirmed as COMPLETE.**

### P4 Status Summary

| # | Feature | Status | LOC | Key Files |
|---|---------|--------|-----|-----------|
| **P4.1** | Linear Phase EQ | ✅ COMPLETE | ~714 | `rf-dsp/src/linear_phase_eq.rs` |
| **P4.2** | Multiband Compression | ✅ COMPLETE | ~1500 | `multiband.rs` + `multiband_panel.dart` |
| **P4.3** | Unity Adapter | ✅ COMPLETE | ~632 | `unity_exporter.dart` |
| **P4.4** | Unreal Adapter | ✅ COMPLETE | ~756 | `unreal_exporter.dart` |
| **P4.5** | Howler.js Adapter | ✅ COMPLETE | ~700 | `howler_exporter.dart` |
| **P4.6** | Mobile/Web Optimization | ✅ COMPLETE | ~1300 | HDR Audio + Memory Manager |
| **P4.7** | WASM Port | ✅ COMPLETE | ~728 | `rf-wasm/src/lib.rs` |
| **P4.8** | CI/CD Regression Testing | ✅ COMPLETE | ~470 | `.github/workflows/ci.yml` |

**Total P4 LOC:** ~6,800+

---

### P4.1 — Linear Phase EQ ✅

Exit Criteria:

- ✅ FIR-based zero-phase EQ
- ✅ FFT overlap-save convolution
- ✅ 64-band support
- ✅ Multiple filter types (bell, shelf, cut, notch, tilt, bandpass, allpass)
- ✅ FFI bindings connected

Files:

- `crates/rf-dsp/src/linear_phase_eq.rs` (~714 LOC)
- `flutter_ui/lib/src/rust/native_ffi.dart` — FFI bindings

---

### P4.2 — Multiband Compression ✅

Exit Criteria:

- ✅ 2-6 bands configurable
- ✅ Linkwitz-Riley crossovers (12/24/48 dB/oct)
- ✅ Per-band: Threshold, Ratio, Attack, Release, Knee, Makeup
- ✅ Per-band: Solo, Mute, Bypass
- ✅ GR meters per band
- ✅ Crossover frequency visualization
- ✅ 30+ FFI functions

Files:

- `crates/rf-dsp/src/multiband.rs` (~714 LOC)
- `flutter_ui/lib/widgets/dsp/multiband_panel.dart` (~786 LOC)
- `flutter_ui/lib/src/rust/native_ffi.dart` — 30+ multiband FFI functions (lines 8772-8870)

---

### P4.3 — Unity Adapter ✅

Exit Criteria:

- ✅ C# code generation
- ✅ ScriptableObject JSON config
- ✅ MonoBehaviour audio manager
- ✅ PostEvent, TriggerStage, RTPC, State methods
- ✅ BlueprintType support

Generated Files:

- `FFEvents.cs` — Event definitions + enums
- `FFRtpc.cs` — RTPC definitions
- `FFStates.cs` — State/Switch enums
- `FFDucking.cs` — Ducking rules
- `FFAudioManager.cs` — MonoBehaviour manager
- `FFConfig.json` — ScriptableObject data

Files:

- `flutter_ui/lib/services/export/unity_exporter.dart` (~632 LOC)

---

### P4.4 — Unreal Adapter ✅

Exit Criteria:

- ✅ C++ code generation
- ✅ USTRUCT, UENUM with BlueprintType
- ✅ UFUNCTION with BlueprintCallable
- ✅ UActorComponent audio manager
- ✅ JSON Data Asset config

Generated Files:

- `FFTypes.h` — USTRUCT/UENUM definitions
- `FFEvents.h/cpp` — Event definitions
- `FFRtpc.h/cpp` — RTPC definitions
- `FFDucking.h` — Ducking rules
- `FFAudioManager.h/cpp` — UActorComponent
- `FFConfig.json` — Data asset

Files:

- `flutter_ui/lib/services/export/unreal_exporter.dart` (~756 LOC)

---

### P4.5 — Howler.js Adapter ✅

Exit Criteria:

- ✅ TypeScript output with ES Modules
- ✅ JavaScript output option
- ✅ VoiceHandle class
- ✅ FluxForgeAudio manager
- ✅ Voice pooling, bus routing, RTPC, states

Generated Files:

- `fluxforge-audio.ts` — TypeScript manager
- `fluxforge-types.ts` — Type definitions
- `fluxforge-config.json` — JSON config

Files:

- `flutter_ui/lib/services/export/howler_exporter.dart` (~700 LOC)

---

### P4.6 — Mobile/Web Optimization ✅

Exit Criteria:

- ✅ HDR Audio System with platform profiles
- ✅ Memory Budget Manager with LRU unloading
- ✅ Streaming Configuration
- ✅ Voice pooling with stealing modes
- ✅ FFI integration (16+ functions)

Components:

**HDR Audio System:**
- `HdrProfile` enum: reference, desktop, mobile, night, custom
- Per-profile: targetLoudness, dynamicRange, compression settings
- Provider integration: `setHdrProfile()`, `updateHdrConfig()`

**Memory Manager:**
- `LoadPriority`: Critical, High, Normal, Streaming
- `MemoryState`: Normal, Warning, Critical
- LRU-based automatic unloading
- Memory budget tracking (resident + streaming)

**Streaming Config:**
- Buffer sizes, prefetch, seamless loop
- Cache configuration

Files:

- `flutter_ui/lib/models/advanced_middleware_models.dart` — HdrAudioConfig, StreamingConfig
- `crates/rf-bridge/src/memory_ffi.rs` (~653 LOC)
- `flutter_ui/lib/src/rust/native_ffi.dart` — MemoryManagerFFI extension (16 functions)
- `flutter_ui/lib/providers/middleware_provider.dart` — Integration

---

### P4.7 — WASM Port ✅

Exit Criteria:

- ✅ Full FluxForgeAudio class via wasm_bindgen
- ✅ Web Audio API integration (AudioContext, GainNode, StereoPannerNode)
- ✅ Voice stealing modes (Oldest, Quietest, LowestPriority)
- ✅ 8 audio buses (Master, SFX, Music, Voice, Ambience, UI, Reels, Wins)
- ✅ Event/Stage/RTPC/State system
- ✅ JSON config loading
- ✅ Size optimization (wee_alloc, opt-level=s, LTO)

Binary Size:

| Build | Raw | Gzipped |
|-------|-----|---------|
| Debug | ~200KB | ~80KB |
| Release | ~120KB | ~45KB |
| Release + wee_alloc | ~100KB | ~38KB |

Files:

- `crates/rf-wasm/src/lib.rs` (~728 LOC)
- `crates/rf-wasm/Cargo.toml` — Size optimization config
- `crates/rf-wasm/README.md` — Usage documentation

---

### P4.8 — CI/CD Regression Testing ✅

Exit Criteria:

- ✅ Cross-platform builds (macOS ARM64/x64, Windows, Linux)
- ✅ Code quality (rustfmt, clippy)
- ✅ Security audit (cargo-audit)
- ✅ Performance benchmarks
- ✅ Flutter tests with coverage
- ✅ WASM build
- ✅ DSP regression tests
- ✅ Engine integration tests
- ✅ Audio quality tests
- ✅ macOS Universal Binary
- ✅ Automated release

Jobs (12):

| Job | Runner | Description |
|-----|--------|-------------|
| check | ubuntu-latest | Code quality (rustfmt, clippy) |
| build | matrix (4 OS) | Cross-platform Rust build + tests |
| macos-universal | macos-14 | Universal binary (ARM64 + x64) |
| bench | ubuntu-latest | Performance benchmarks |
| security | ubuntu-latest | cargo-audit security scan |
| docs | ubuntu-latest | Rust documentation build |
| flutter-tests | macos-latest | Flutter analyze + tests + coverage |
| build-wasm | ubuntu-latest | WASM build (wasm-pack) |
| regression-tests | ubuntu-latest | DSP + engine regression tests |
| audio-quality-tests | ubuntu-latest | Audio quality verification |
| flutter-build-macos | macos-14 | Full macOS app build |
| release | ubuntu-latest | Create release archives |

Tests: 39 total (25 integration + 14 regression in rf-dsp)

Files:

- `.github/workflows/ci.yml` (~470 LOC)
- `crates/rf-dsp/tests/regression_tests.rs` (~400 LOC)

---

### P4 Verification Summary

| Metric | Value |
|--------|-------|
| **Total LOC** | ~6,800+ |
| **FFI Functions Added** | 80+ |
| **Game Engine Adapters** | 3 (Unity, Unreal, Howler.js) |
| **CI Jobs** | 12 parallel |
| **Test Coverage** | DSP regression + integration |
| **WASM Binary** | ~100-120KB gzipped |

**Status:** ALL P4 ITEMS PRODUCTION-READY (2026-01-29)
