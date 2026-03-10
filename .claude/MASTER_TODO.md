# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-10 | **Analyzer:** 0 errors

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+ lines) | `slot_lab_coordinator.dart` |
| SlotLab providers | `slot_engine_provider.dart`, `slot_stage_provider.dart`, `slot_audio_provider.dart` | |
| Mixer | `engine_connected_layout.dart` | `mixer_provider.dart` |
| FFI | `native_ffi.dart` (21K+ lines) | `crates/rf-bridge/src/lib.rs` |
| Offline DSP | `offline_processing_provider.dart` | `crates/rf-offline/src/pipeline.rs` |
| SFX Pipeline | `sfx_pipeline_service.dart`, `sfx_pipeline_wizard.dart` | `sfx_pipeline_config.dart` |
| DI | `service_locator.dart` | `main.dart` (provider tree) |
| Commands | `command_registry.dart` | |

## Active Traps

- `slot_lab_screen.dart` — 13K+ lines, NE MOŽE se razbiti (Dart State class limitation)
- `native_ffi.dart` — 21K+ lines, auto-generated, READ ONLY
- `OfflineOutputFormat` enum nema OGG/AAC — SFX pipeline koristi raw FFI format ID-jeve
- `slot_lab_provider.dart` je MRTAV KOD — koristi se `SlotLabCoordinator` (typedef)
- Dirty files: `rf-plugin/`, `plugin_provider.dart`, `plugins_scanner_panel.dart` — VST hosting WIP

## Remaining / Planned

_(dodaj nove taskove ovde)_
