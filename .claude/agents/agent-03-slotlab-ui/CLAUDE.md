# Agent 3: SlotLabUI

## Role
SlotLab screen rendering, coordinator, lower zone tabs, UCP, preview widgets.

## File Ownership (~70 files)

### Core
- `flutter_ui/lib/screens/slot_lab_screen.dart` (13000+ lines — ALWAYS read with offset/limit)
- `flutter_ui/lib/providers/slot_lab/slot_lab_coordinator.dart` (THE coordinator)
- `flutter_ui/lib/providers/slot_lab/slot_engine_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slot_stage_provider.dart`
- `flutter_ui/lib/providers/slot_lab/inspector_context_provider.dart`
- `flutter_ui/lib/providers/slot_lab/smart_collapsing_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slotlab_notification_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slotlab_undo_provider.dart`
- `flutter_ui/lib/providers/slot_lab/config_undo_manager.dart`
- `flutter_ui/lib/providers/slot_lab/error_prevention_provider.dart`

### Lower Zone Tabs (10)
- `widgets/slot_lab/lower_zone/` — slotlab_intel_tab, slotlab_logic_tab, slotlab_monitor_tab, slotlab_containers_tab, slotlab_rtpc_tab, slotlab_music_tab, slotlab_music_layers_panel, event_list_panel, command_builder_panel, bus_meters_panel

## Critical Rules
1. **SlotLabProvider is DEAD CODE** — use `SlotLabCoordinator`
2. **slot_lab_screen.dart: NEVER read entire file** — use offset/limit
3. EventRegistry: ONE registration path — ONLY `_syncEventToRegistry()`
4. NEVER register in `composite_event_system_provider.dart`
5. ID format: `event.id`, NEVER `composite_${id}_${STAGE}`
6. Context Bar ROW 2: ONLY Undo/Redo (left) + Toast (right)
7. Win tier: NEVER hardcode labels/colors/icons — use WinTierConfig

## Forbidden
- NEVER read slot_lab_screen.dart without offset/limit
- NEVER use SlotLabProvider (dead code)
- NEVER add a second EventRegistry registration path
