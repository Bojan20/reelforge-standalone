# Agent 9: ProjectIO

## Role
Save/load, project format, import/export, audio format, publish pipeline, asset browser.

## File Ownership (~15 files)

### Rust
- `crates/rf-bridge/src/project_ffi.rs`
- `crates/rf-bridge/src/api_project.rs`
- `crates/rf-engine/src/audio_import.rs`
- `crates/rf-engine/src/export.rs`

### Dart
- `flutter_ui/lib/src/rust/engine_api.dart` (save/load section)
- `flutter_ui/lib/services/session_template_service.dart`

### Widgets
- `flutter_ui/lib/widgets/export/` (1 file) — loudness analysis panel
- `flutter_ui/lib/widgets/publish/` (1 file) — publish pipeline panel
- `flutter_ui/lib/widgets/browser/` (1 file) — audio pool browser
- `flutter_ui/lib/widgets/audio/` (1 file) — variant group panel

## Critical Rules
1. `project_save` / `project_load` are in rf-bridge (NOT deprecated stubs)
2. Audio SRC: Lanczos-3 sinc interpolation for export
3. Import: NO SRC on import (Reaper-style — use original sample rate)
4. `toNativeUtf8()` allocates with calloc → MUST `calloc.free()`, NEVER `malloc.free()`
5. Automation serialization: CurveType + ParamId must be preserved
6. Clip properties (fade, gain, pitch) included in project save

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 4 | CRITICAL | OutputBus serialization (shared with MixerArchitect) | session_template_service.dart:47,58 |

## Relationships
- **MixerArchitect (2):** Session template includes mixer state
- **AudioEngine (1):** Engine state serialized via rf-bridge
- **BuildOps (10):** rf-offline for batch export processing
- **TimelineEngine (12):** Clip/track state in project files

## Forbidden
- NEVER use deprecated project stubs — only rf-bridge project_ffi.rs
- NEVER apply SRC on import
- NEVER use malloc.free() for Dart FFI strings (use calloc.free())
