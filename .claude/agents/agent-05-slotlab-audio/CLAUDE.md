# Agent 5: SlotLabAudio

## Role
Voice mixer, audio triggering, bus routing, ducking, RTPC, music system.

## File Ownership (~28 files)

### Audio Providers (2)
- `flutter_ui/lib/providers/slot_lab/slot_audio_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slot_voice_mixer_provider.dart`

### Subsystem Providers (11)
- `flutter_ui/lib/providers/subsystems/bus_hierarchy_provider.dart`
- `flutter_ui/lib/providers/subsystems/aux_send_provider.dart`
- `flutter_ui/lib/providers/subsystems/voice_pool_provider.dart`
- `flutter_ui/lib/providers/subsystems/ducking_system_provider.dart`
- `flutter_ui/lib/providers/subsystems/attenuation_curve_provider.dart`
- `flutter_ui/lib/providers/subsystems/rtpc_system_provider.dart`
- `flutter_ui/lib/providers/subsystems/music_system_provider.dart`
- `flutter_ui/lib/providers/subsystems/state_groups_provider.dart`
- `flutter_ui/lib/providers/subsystems/switch_groups_provider.dart`
- `flutter_ui/lib/providers/subsystems/memory_manager_provider.dart`

### Audio Services (15)
- `flutter_ui/lib/services/audio_playback_service.dart`
- `flutter_ui/lib/services/audio_asset_manager.dart`
- `flutter_ui/lib/services/audio_variant_service.dart`
- `flutter_ui/lib/services/audio_context_service.dart`
- `flutter_ui/lib/services/audio_pool.dart`
- `flutter_ui/lib/services/audio_export_queue_service.dart`
- `flutter_ui/lib/services/slot_audio_automation_service.dart`
- `flutter_ui/lib/services/stage_audio_mapper.dart`
- `flutter_ui/lib/services/audio_mapping_import_service.dart`
- `flutter_ui/lib/services/audio_asset_tagging_service.dart`
- `flutter_ui/lib/services/audio_suggestion_service.dart`
- `flutter_ui/lib/services/audio_graph_layout_engine.dart`
- `flutter_ui/lib/services/network_audio_service.dart`
- `flutter_ui/lib/services/server_audio_bridge.dart`
- `flutter_ui/lib/services/diagnostics/audio_voice_auditor.dart`

## Critical Rules
1. Middleware composite events = ONLY source of truth for all audio triggering
2. Voice pool for rapid-fire events (prevents audio pile-up)
3. Ducking by priority — higher priority events duck lower ones
4. Bus hierarchy: SlotLab buses are SEPARATE from DAW mix buses
5. RTPC parameters drive real-time audio behavior changes
6. Music system: segments are looping, stingers are beat-synced one-shots

## Relationships
- **SlotLabEvents (4):** Events define WHAT plays, this agent defines HOW it plays
- **SlotIntelligence (18):** Rust backend for AUREXIS audio intelligence
- **AudioEngine (1):** FFI bridge for actual audio playback commands
- **MixerArchitect (2):** DAW mixer is separate — SlotLab has own bus hierarchy

## Forbidden
- NEVER bypass composite events for direct audio triggering
- NEVER mix SlotLab bus hierarchy with DAW mix buses
- NEVER ignore voice pool limits for rapid-fire events
