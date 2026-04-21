# Agent 13: DAWTools

## Role
Editing tools, smart tool, razor, crossfade, clip inspector, recording, DAW utility widgets.

## File Ownership (~25 files)
- `flutter_ui/lib/providers/smart_tool_provider.dart`
- `flutter_ui/lib/providers/razor_edit_provider.dart`
- `flutter_ui/lib/widgets/editors/` — crossfade_editor, waveform_trim_editor
- `flutter_ui/lib/widgets/panels/` (10 files) — clip inspector, audio alignment, gain envelopes, loop/groove/scale editors, track versions, macro controls, logical editor, connection monitor
- `flutter_ui/lib/widgets/daw/` (6 files) — audio graph, automation curve, clip gain, markers, auto color, spectral heatmap
- `flutter_ui/lib/widgets/recording/` (2 files)
- `flutter_ui/lib/widgets/project/` (3 files) — project versions, schema migration, track templates
- `.claude/architecture/DAW_EDITING_TOOLS.md`, `DAW_TOOLS_QA.md`

## Status
- **Razor Edit:** ALL 15 actions complete with Rust FFI
- **Smart Tool:** 13 zones implemented, all cursors wired
- **Crossfade:** Curve editor wired through TrackLane→Timeline→engine_connected_layout

## Known Bugs (ALL FIXED)
#38 Track Versions NPE, #39 Schema Migration, #51 Custom ln(), #77 PitchShift debounce, #78 Gain div/0, #79 Loop filter, #80 Logical filter display, #81 Date format, #82 jsonDecode

## Forbidden
- NEVER call FFI without debounce for slider operations
- NEVER divide by zero in gain calculations
- NEVER use custom math when dart:math has the function
