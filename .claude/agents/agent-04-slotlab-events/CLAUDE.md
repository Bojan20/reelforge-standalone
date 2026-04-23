# Agent 4: SlotLabEvents

## Role
EventRegistry, CompositeEventSystem, Middleware, CustomEvents, FFNC, middleware UI widgets.

## File Ownership (~75 files)

### Event System Core (6)
- `flutter_ui/lib/services/event_registry.dart`
- `flutter_ui/lib/services/event_sync_service.dart`
- `flutter_ui/lib/services/event_collision_detector.dart`
- `flutter_ui/lib/services/event_dependency_analyzer.dart`
- `flutter_ui/lib/services/event_naming_service.dart`
- `flutter_ui/lib/services/diagnostics/event_flow_monitor.dart`

### Composite Event System (3)
- `flutter_ui/lib/providers/subsystems/composite_event_system_provider.dart`
- `flutter_ui/lib/providers/subsystems/event_system_provider.dart`
- `flutter_ui/lib/providers/subsystems/event_profiler_provider.dart`

### FFNC (12)
- `flutter_ui/lib/services/ffnc/` — parser, renamer, validator, presets, phase_presets, stage_defaults, template_generator, template_library, profile_importer, profile_exporter, readme_generator
- `flutter_ui/lib/widgets/slot_lab/ffnc_rename_dialog.dart`

### Middleware UI (46)
- `flutter_ui/lib/widgets/middleware/` — complete middleware UI system

## Critical Rules
1. **EventRegistry: ONE registration path** — ONLY `_syncEventToRegistry()` in slot_lab_screen.dart
2. **NEVER register in composite_event_system_provider.dart**
3. Middleware composite events = **ONLY source of truth** for all SlotLab audio
4. ID format: `event.id`, NEVER `composite_${id}_${STAGE}`
5. FFNC prefixes: `sfx_`, `mus_`, `amb_`, `trn_`, `ui_`, `vo_`
6. BIG_WIN_START/END are `mus_` (music bus), NOT `sfx_`
7. `hasExplicitFadeActions` MUST include FadeVoice/StopVoice

## Forbidden
- NEVER add a second EventRegistry registration path
- NEVER use composite_${id}_${STAGE} format
- NEVER assign BIG_WIN events to sfx_ prefix — they are mus_
