# FluxForge Studio Development Roadmap

## Kompletan pregled svega što treba implementirati

**Generisano:** 2026-01-05
**Status:** 68,459+ linija koda, ~80% kompletno
**Cilj:** AAA DAW koji nadmašuje Cubase, Pro Tools, Ableton, Logic, REAPER

---

## TIER 0: KRITIČNO — Bez ovoga ne radi

### 0.1 Audio I/O System
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| ASIO device enumeration (Windows) | `crates/rf-audio/src/asio.rs` | M | P0 |
| ASIO device selection UI | `flutter_ui/lib/widgets/settings/audio_device_selector.dart` | M | P0 |
| CoreAudio device enumeration (macOS) | `crates/rf-audio/src/coreaudio.rs` | M | P0 |
| JACK/PipeWire support (Linux) | `crates/rf-audio/src/jack.rs` | M | P0 |
| Device latency reporting | `crates/rf-audio/src/latency.rs` | S | P0 |
| Input routing matrix | `crates/rf-audio/src/routing.rs` | L | P0 |
| Output routing matrix | `crates/rf-audio/src/routing.rs` | L | P0 |
| Sample rate switching | `crates/rf-audio/src/device.rs` | S | P0 |
| Buffer size switching | `crates/rf-audio/src/device.rs` | S | P0 |

### 0.2 File Operations
Status: **DELIMIČNO**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Project save (.rfproj) | `crates/rf-state/src/project_io.rs` | M | P0 |
| Project load | `crates/rf-state/src/project_io.rs` | M | P0 |
| Save As dialog | `flutter_ui/lib/dialogs/save_project_dialog.dart` | S | P0 |
| Recent projects list | `flutter_ui/lib/providers/recent_projects_provider.dart` | S | P0 |
| Auto-save implementation | `crates/rf-state/src/autosave.rs` | M | P0 |
| Crash recovery | `crates/rf-state/src/recovery.rs` | M | P1 |
| Backup system | `crates/rf-state/src/backup.rs` | S | P1 |

### 0.3 Recording
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Audio recording to disk | `crates/rf-engine/src/recording.rs` | L | P0 |
| Disk streaming (write) | `crates/rf-file/src/disk_writer.rs` | M | P0 |
| Punch in/out | `crates/rf-engine/src/punch.rs` | M | P0 |
| Pre-roll/post-roll | `crates/rf-engine/src/preroll.rs` | S | P1 |
| Loop recording | `crates/rf-engine/src/loop_record.rs` | M | P1 |
| Takes management | `crates/rf-engine/src/takes.rs` | M | P1 |
| Input monitoring | `crates/rf-engine/src/monitoring.rs` | M | P0 |
| Latency compensation UI | `flutter_ui/lib/widgets/settings/latency_settings.dart` | S | P0 |

### 0.4 Export/Bounce
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Offline bounce engine | `crates/rf-engine/src/bounce.rs` | L | P0 |
| WAV export (16/24/32-bit) | `crates/rf-file/src/wav_export.rs` | M | P0 |
| FLAC export | `crates/rf-file/src/flac_export.rs` | M | P1 |
| MP3 export (LAME) | `crates/rf-file/src/mp3_export.rs` | M | P2 |
| Export dialog UI | `flutter_ui/lib/dialogs/export_dialog.dart` | M | P0 |
| Progress indicator | `flutter_ui/lib/widgets/common/export_progress.dart` | S | P0 |
| Stem export | `crates/rf-engine/src/stem_export.rs` | M | P1 |
| Batch export | `crates/rf-engine/src/batch_export.rs` | M | P2 |
| Loudness normalization | `crates/rf-dsp/src/loudness_norm.rs` | M | P1 |

---

## TIER 1: CORE DAW — Bez ovoga nije pravi DAW

### 1.1 MIDI Editor (Piano Roll)
Status: **DELIMIČNO** (backend kompletan, UI započet)

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Piano roll grid rendering | `flutter_ui/lib/widgets/editors/piano_roll/grid.dart` | M | P0 |
| Note drawing tool | `flutter_ui/lib/widgets/editors/piano_roll/note_tool.dart` | M | P0 |
| Note selection (multi) | `flutter_ui/lib/widgets/editors/piano_roll/selection.dart` | M | P0 |
| Note drag (move) | `flutter_ui/lib/widgets/editors/piano_roll/note_drag.dart` | S | P0 |
| Note resize (duration) | `flutter_ui/lib/widgets/editors/piano_roll/note_resize.dart` | S | P0 |
| Velocity editor lane | `flutter_ui/lib/widgets/editors/piano_roll/velocity_lane.dart` | M | P0 |
| Velocity drawing | `flutter_ui/lib/widgets/editors/piano_roll/velocity_draw.dart` | S | P0 |
| Quantize UI | `flutter_ui/lib/widgets/editors/piano_roll/quantize_panel.dart` | S | P0 |
| Transpose dialog | `flutter_ui/lib/dialogs/transpose_dialog.dart` | S | P1 |
| Scale highlight | `flutter_ui/lib/widgets/editors/piano_roll/scale_highlight.dart` | S | P2 |
| Chord recognition | `crates/rf-core/src/chord.rs` | M | P2 |
| MIDI input routing | `crates/rf-engine/src/midi_input.rs` | M | P0 |
| MIDI step input | `flutter_ui/lib/widgets/editors/piano_roll/step_input.dart` | M | P1 |

### 1.2 Drum Editor
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Drum grid layout | `flutter_ui/lib/widgets/editors/drum_editor/grid.dart` | M | P1 |
| Drum map support | `crates/rf-core/src/drum_map.rs` | M | P1 |
| GM drum names | `crates/rf-core/src/gm_drums.rs` | S | P1 |
| Velocity color coding | `flutter_ui/lib/widgets/editors/drum_editor/velocity_colors.dart` | S | P1 |
| Pattern preset library | `flutter_ui/lib/widgets/editors/drum_editor/patterns.dart` | M | P2 |

### 1.3 CC/Automation Editor
Status: **DELIMIČNO**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| CC lane rendering | `flutter_ui/lib/widgets/editors/automation/cc_lane.dart` | M | P0 |
| Curve drawing (bezier) | `flutter_ui/lib/widgets/editors/automation/curve_draw.dart` | M | P0 |
| Point editing | `flutter_ui/lib/widgets/editors/automation/point_edit.dart` | S | P0 |
| CC selector dropdown | `flutter_ui/lib/widgets/editors/automation/cc_selector.dart` | S | P0 |
| Multiple CC lanes | `flutter_ui/lib/widgets/editors/automation/multi_lane.dart` | M | P1 |
| Expression maps | `crates/rf-core/src/expression_map.rs` | L | P2 |
| Automation shapes | `flutter_ui/lib/widgets/editors/automation/shapes.dart` | M | P1 |

### 1.4 Plugin Hosting
Status: **DELIMIČNO** (arhitektura gotova, procesiranje nedostaje)

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| VST3 audio processing | `crates/rf-plugin/src/vst3_process.rs` | XL | P0 |
| VST3 parameter sync | `crates/rf-plugin/src/vst3_params.rs` | M | P0 |
| VST3 GUI embedding | `crates/rf-plugin/src/vst3_gui.rs` | L | P1 |
| VST3 preset loading | `crates/rf-plugin/src/vst3_preset.rs` | M | P1 |
| CLAP audio processing | `crates/rf-plugin/src/clap_process.rs` | L | P1 |
| CLAP GUI embedding | `crates/rf-plugin/src/clap_gui.rs` | M | P1 |
| AU loading (macOS) | `crates/rf-plugin/src/au_process.rs` | L | P2 |
| Plugin scanner dialog | `flutter_ui/lib/dialogs/plugin_scanner_dialog.dart` | M | P0 |
| Plugin browser tree | `flutter_ui/lib/widgets/browser/plugin_browser.dart` | M | P0 |
| Plugin favorites | `flutter_ui/lib/providers/plugin_favorites_provider.dart` | S | P1 |
| Plugin search | `flutter_ui/lib/widgets/browser/plugin_search.dart` | S | P0 |

### 1.5 Pitch Editor (VariAudio-style)
Status: **NEDOSTAJE** (DSP postoji, UI ne)

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Pitch curve display | `flutter_ui/lib/widgets/editors/pitch_editor/curve.dart` | L | P1 |
| Note segment detection | `crates/rf-dsp/src/pitch_segment.rs` | L | P1 |
| Segment drag (pitch) | `flutter_ui/lib/widgets/editors/pitch_editor/segment_drag.dart` | M | P1 |
| Vibrato detection | `crates/rf-dsp/src/vibrato_detect.rs` | M | P1 |
| Vibrato editing | `flutter_ui/lib/widgets/editors/pitch_editor/vibrato_edit.dart` | M | P1 |
| Formant preservation UI | `flutter_ui/lib/widgets/editors/pitch_editor/formant.dart` | S | P1 |
| Pitch snap to scale | `crates/rf-dsp/src/pitch_snap.rs` | M | P1 |
| Pitch straighten tool | `flutter_ui/lib/widgets/editors/pitch_editor/straighten.dart` | S | P1 |

### 1.6 Time Stretch (Elastic Audio)
Status: **DSP KOMPLETAN, UI nedostaje**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Warp marker display | `flutter_ui/lib/widgets/editors/warp/marker_display.dart` | M | P1 |
| Warp marker drag | `flutter_ui/lib/widgets/editors/warp/marker_drag.dart` | M | P1 |
| Free warp mode | `flutter_ui/lib/widgets/editors/warp/free_warp.dart` | M | P1 |
| Tempo-based warp | `flutter_ui/lib/widgets/editors/warp/tempo_warp.dart` | M | P1 |
| Algorithm selector | `flutter_ui/lib/widgets/editors/warp/algorithm_selector.dart` | S | P1 |
| Quality preview | `flutter_ui/lib/widgets/editors/warp/quality_preview.dart` | S | P2 |

---

## TIER 2: PROFESSIONAL — Pro workflow features

### 2.1 Control Room / Monitor Management
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Control room data model | `crates/rf-core/src/control_room.rs` | M | P2 |
| Monitor source selector | `flutter_ui/lib/widgets/control_room/source_selector.dart` | M | P2 |
| Speaker set management | `flutter_ui/lib/widgets/control_room/speaker_sets.dart` | M | P2 |
| Dim/Mono buttons | `flutter_ui/lib/widgets/control_room/dim_mono.dart` | S | P2 |
| Talkback system | `crates/rf-engine/src/talkback.rs` | M | P2 |
| Cue mix system | `crates/rf-engine/src/cue_mix.rs` | L | P2 |
| External input routing | `crates/rf-engine/src/external_input.rs` | M | P2 |

### 2.2 Video Integration
Status: **BACKEND KOMPLETAN, UI nedostaje**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Video track display | `flutter_ui/lib/widgets/timeline/video_track.dart` | L | P2 |
| Video preview window | `flutter_ui/lib/widgets/video/preview_window.dart` | L | P2 |
| Frame-accurate sync UI | `flutter_ui/lib/widgets/video/sync_controls.dart` | M | P2 |
| Timecode display | `flutter_ui/lib/widgets/video/timecode_display.dart` | S | P2 |
| Video import dialog | `flutter_ui/lib/dialogs/video_import_dialog.dart` | M | P2 |
| AAF/OMF import | `crates/rf-file/src/aaf_import.rs` | XL | P2 |
| AAF/OMF export | `crates/rf-file/src/aaf_export.rs` | XL | P2 |
| EDL import/export | `crates/rf-file/src/edl.rs` | L | P2 |

### 2.3 Advanced Routing
Status: **ENGINE KOMPLETAN, UI delimično**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Routing matrix UI | `flutter_ui/lib/widgets/routing/matrix.dart` | L | P1 |
| Sidechain picker | `flutter_ui/lib/widgets/routing/sidechain_picker.dart` | M | P1 |
| Send amount knob | `flutter_ui/lib/widgets/mixer/send_knob.dart` | S | P1 |
| Pre/post fader toggle | `flutter_ui/lib/widgets/mixer/pre_post_toggle.dart` | S | P1 |
| Direct out routing | `flutter_ui/lib/widgets/routing/direct_out.dart` | M | P1 |
| Bus assignment dropdown | `flutter_ui/lib/widgets/mixer/bus_assign.dart` | S | P1 |
| Surround panner (5.1/7.1) | `flutter_ui/lib/widgets/panner/surround_panner.dart` | L | P2 |

### 2.4 Comping System
Status: **DELIMIČNO** (UI postoji, engine integracija nedostaje)

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Lane expand/collapse | `flutter_ui/lib/widgets/timeline/lane_collapse.dart` | S | P1 |
| Take selection in lane | `flutter_ui/lib/widgets/timeline/take_select.dart` | M | P1 |
| Comp to new track | `crates/rf-engine/src/comp_flatten.rs` | M | P1 |
| Crossfade at comp points | `crates/rf-engine/src/comp_crossfade.rs` | M | P1 |
| Quick-swap keys (1-9) | `flutter_ui/lib/providers/comp_shortcuts.dart` | S | P1 |

### 2.5 Markers & Regions
Status: **DELIMIČNO**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Marker track display | `flutter_ui/lib/widgets/timeline/marker_track.dart` | M | P1 |
| Marker editing dialog | `flutter_ui/lib/dialogs/marker_edit_dialog.dart` | S | P1 |
| Marker navigation | `flutter_ui/lib/providers/marker_navigation.dart` | S | P1 |
| Cycle markers (regions) | `crates/rf-core/src/cycle_marker.rs` | M | P1 |
| Arranger track | `flutter_ui/lib/widgets/timeline/arranger_track.dart` | L | P2 |
| Arranger chain | `crates/rf-engine/src/arranger_chain.rs` | M | P2 |

---

## TIER 3: COMPETITIVE EDGE — Features za superiornost

### 3.1 Session View (Ableton-style)
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Session view layout | `flutter_ui/lib/screens/session_view.dart` | XL | P3 |
| Clip slot widget | `flutter_ui/lib/widgets/session/clip_slot.dart` | M | P3 |
| Scene launcher | `flutter_ui/lib/widgets/session/scene_launcher.dart` | M | P3 |
| Clip launch quantize | `crates/rf-engine/src/clip_launch.rs` | M | P3 |
| Follow actions | `crates/rf-engine/src/follow_actions.rs` | L | P3 |
| Record to slot | `crates/rf-engine/src/slot_record.rs` | M | P3 |
| Scene to arrangement | `crates/rf-engine/src/scene_to_arrange.rs` | M | P3 |

### 3.2 Dolby Atmos / Spatial Audio
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Object-based panner | `flutter_ui/lib/widgets/spatial/object_panner.dart` | XL | P3 |
| 7.1.4 bed routing | `crates/rf-engine/src/atmos_bed.rs` | L | P3 |
| Object automation | `crates/rf-engine/src/object_automation.rs` | L | P3 |
| Binaural preview | `crates/rf-dsp/src/binaural.rs` | L | P3 |
| ADM BWF export | `crates/rf-file/src/adm_bwf.rs` | XL | P3 |
| Atmos renderer | `crates/rf-dsp/src/atmos_renderer.rs` | XL | P3 |
| Height panner | `flutter_ui/lib/widgets/spatial/height_panner.dart` | M | P3 |
| Room visualization | `flutter_ui/lib/widgets/spatial/room_viz.dart` | L | P3 |

### 3.3 AI Features
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Stem separation (Demucs) | `crates/rf-ml/src/stem_split.rs` | XL | P3 |
| AI tempo detection | `crates/rf-ml/src/tempo_ai.rs` | L | P3 |
| Mastering assistant | `crates/rf-ml/src/mastering_ai.rs` | XL | P3 |
| Vocal isolation | `crates/rf-ml/src/vocal_isolate.rs` | XL | P3 |
| Drum transcription | `crates/rf-ml/src/drum_transcribe.rs` | L | P3 |
| Chord detection | `crates/rf-ml/src/chord_ai.rs` | M | P3 |
| Smart EQ suggestions | `crates/rf-ml/src/eq_suggest.rs` | L | P3 |

### 3.4 Beat Detective / Transient Editing
Status: **DSP POSTOJI, UI nedostaje**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Transient marker display | `flutter_ui/lib/widgets/editors/transient/marker_display.dart` | M | P2 |
| Sensitivity slider | `flutter_ui/lib/widgets/editors/transient/sensitivity.dart` | S | P2 |
| Slice to MIDI | `crates/rf-engine/src/slice_to_midi.rs` | M | P2 |
| Quantize to grid | `crates/rf-engine/src/transient_quantize.rs` | M | P2 |
| Groove extraction | `crates/rf-engine/src/groove_extract.rs` | M | P2 |
| Groove template apply | `crates/rf-engine/src/groove_apply.rs` | M | P2 |

### 3.5 Score Editor
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Staff notation render | `flutter_ui/lib/widgets/editors/score/staff.dart` | XL | P4 |
| Note entry (mouse) | `flutter_ui/lib/widgets/editors/score/note_entry.dart` | L | P4 |
| Clef/key/time sig | `flutter_ui/lib/widgets/editors/score/signatures.dart` | M | P4 |
| Lyrics support | `flutter_ui/lib/widgets/editors/score/lyrics.dart` | M | P4 |
| MusicXML export | `crates/rf-file/src/musicxml.rs` | L | P4 |
| PDF score export | `crates/rf-file/src/score_pdf.rs` | L | P4 |

---

## TIER 4: POLISH — Završne funkcije

### 4.1 Preferences / Settings
Status: **DELIMIČNO**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Audio settings page | `flutter_ui/lib/screens/settings/audio_settings.dart` | M | P0 |
| MIDI settings page | `flutter_ui/lib/screens/settings/midi_settings.dart` | M | P1 |
| Plugin settings page | `flutter_ui/lib/screens/settings/plugin_settings.dart` | M | P1 |
| Appearance settings | `flutter_ui/lib/screens/settings/appearance_settings.dart` | S | P2 |
| Shortcut editor | `flutter_ui/lib/screens/settings/shortcut_editor.dart` | L | P2 |
| Project defaults | `flutter_ui/lib/screens/settings/project_defaults.dart` | M | P1 |
| Metering preferences | `flutter_ui/lib/screens/settings/metering_settings.dart` | S | P1 |
| Metronome settings | `flutter_ui/lib/screens/settings/metronome_settings.dart` | S | P1 |

### 4.2 Help / Documentation
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Tooltips (all widgets) | Various | M | P2 |
| Keyboard shortcuts overlay | `flutter_ui/lib/widgets/help/shortcuts_overlay.dart` | M | P2 |
| What's new dialog | `flutter_ui/lib/dialogs/whats_new_dialog.dart` | S | P3 |
| Quick start wizard | `flutter_ui/lib/screens/quick_start.dart` | M | P3 |
| In-app help system | `flutter_ui/lib/widgets/help/help_panel.dart` | L | P3 |

### 4.3 Undo/Redo Improvements
Status: **ENGINE KOMPLETAN, UI delimično**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Undo history panel | `flutter_ui/lib/widgets/history/history_panel.dart` | M | P1 |
| Undo branch navigation | `flutter_ui/lib/widgets/history/branch_nav.dart` | M | P2 |
| Undo descriptions | `crates/rf-state/src/undo_description.rs` | S | P1 |
| Selective undo | `crates/rf-state/src/selective_undo.rs` | L | P3 |

### 4.4 Collaboration
Status: **NEDOSTAJE**

| Task | Fajl | Effort | Prioritet |
|------|------|--------|-----------|
| Project sharing | `crates/rf-collab/src/sharing.rs` | XL | P4 |
| Real-time sync | `crates/rf-collab/src/realtime.rs` | XL | P4 |
| Comments/annotations | `crates/rf-collab/src/comments.rs` | M | P4 |
| Version control | `crates/rf-collab/src/versioning.rs` | L | P4 |

---

## FEATURE COMPARISON MATRIX

### vs Cubase Pro 14

| Feature | Cubase | FluxForge Studio | Gap |
|---------|--------|-----------|-----|
| Audio engine | ✅ | ✅ | - |
| MIDI editing | ✅✅✅ | ⚠️ | UI |
| Score editor | ✅ | ❌ | Full |
| VariAudio | ✅ | ⚠️ DSP only | UI |
| Control Room | ✅ | ❌ | Full |
| Video | ✅ | ⚠️ decoder only | UI |
| Chord track | ✅ | ❌ | Full |
| Expression maps | ✅ | ❌ | Full |
| Plugin hosting | ✅ | ⚠️ | VST3 processing |
| EQ | 8 bands | 64 bands | **Superior** |
| SIMD DSP | SSE | AVX-512 | **Superior** |
| GPU viz | ❌ | ✅ | **Superior** |

### vs Pro Tools

| Feature | Pro Tools | FluxForge Studio | Gap |
|---------|-----------|-----------|-----|
| Audio engine | ✅ | ✅ | - |
| Edit modes | ✅ | ✅ | - |
| Elastic Audio | ✅ | ✅ DSP | UI |
| Beat Detective | ✅ | ⚠️ DSP only | UI |
| Video | ✅✅ | ⚠️ | Full |
| AAF/OMF | ✅ | ❌ | Full |
| VCA | ✅ | ✅ | - |
| Clip gain | ✅ | ✅ | - |
| Track count | 2048 | Unlimited | **Superior** |
| Plugin hosting | ✅ | ⚠️ | AAX |

### vs Ableton Live 12

| Feature | Live | FluxForge Studio | Gap |
|---------|------|-----------|-----|
| Session View | ✅✅✅ | ❌ | Full |
| Arrangement | ✅ | ✅ | - |
| Warping | ✅✅ | ⚠️ | UI |
| MIDI effects | ✅ | ❌ | Full |
| Max for Live | ✅ | ⚠️ rf-script | Different |
| Push integration | ✅ | ❌ | Full |
| Link | ✅ | ✅ | - |
| DSP quality | Good | **Superior** | - |

### vs Logic Pro 11

| Feature | Logic | FluxForge Studio | Gap |
|---------|-------|-----------|-----|
| Audio engine | ✅ | ✅ | - |
| Flex Time | ✅ | ✅ DSP | UI |
| Flex Pitch | ✅ | ⚠️ | UI |
| Session Players | ✅ | ❌ | AI |
| Stem Splitter | ✅ | ❌ | AI |
| Spatial Audio | ✅✅ | ❌ | Full |
| Live Loops | ✅ | ❌ | Full |
| Smart Tempo | ✅ | ⚠️ | Engine |
| Cross-platform | ❌ | ✅ | **Superior** |

### vs REAPER 7

| Feature | REAPER | FluxForge Studio | Gap |
|---------|--------|-----------|-----|
| Track architecture | Unified | Unified | Same |
| Routing | ✅✅ | ✅ | - |
| ReaScript | Lua/EEL/Python | Lua | Similar |
| Custom actions | ✅ | ❌ | Feature |
| Render matrix | ✅ | ❌ | Feature |
| Stretch markers | ✅ | ❌ | Feature |
| Price | $60 | TBD | - |
| EQ quality | Basic | **Superior** | - |
| GPU viz | ❌ | ✅ | **Superior** |

---

## EFFORT LEGEND

- **S** = Small (1-2 days)
- **M** = Medium (3-5 days)
- **L** = Large (1-2 weeks)
- **XL** = Extra Large (2-4 weeks)

## PRIORITY LEGEND

- **P0** = Must have for beta release
- **P1** = Must have for v1.0
- **P2** = Should have for v1.0
- **P3** = Nice to have
- **P4** = Future version

---

## SUMMARY BY TIER

| Tier | Tasks | Total Effort | Priority |
|------|-------|--------------|----------|
| TIER 0 (Critical) | 26 tasks | ~2-3 months | **NOW** |
| TIER 1 (Core DAW) | 52 tasks | ~4-6 months | Q1-Q2 |
| TIER 2 (Professional) | 38 tasks | ~3-4 months | Q2-Q3 |
| TIER 3 (Competitive) | 42 tasks | ~6-8 months | Q3-Q4 |
| TIER 4 (Polish) | 18 tasks | ~2 months | Ongoing |
| **TOTAL** | **176 tasks** | **~18-24 months** | - |

---

## IMMEDIATE NEXT STEPS (This Week)

1. **Audio device selection UI** - Enable users to select ASIO/CoreAudio device
2. **Project save/load** - Basic persistence
3. **VST3 audio processing** - Complete vst3-sys binding
4. **Recording to disk** - Basic audio recording
5. **Export dialog** - WAV export with progress

---

## CODE QUALITY METRICS

| Metric | Current | Target |
|--------|---------|--------|
| Total lines | 68,459+ | 150,000+ |
| Test coverage | ~30% | 80% |
| Documentation | ~40% | 90% |
| Performance | Excellent | Excellent |
| Memory safety | 100% (Rust) | 100% |

---

*Generisano automatski od strane Claude Code*
*FluxForge Studio DAW Development Roadmap*
