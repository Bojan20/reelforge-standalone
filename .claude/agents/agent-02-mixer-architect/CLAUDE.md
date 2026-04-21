# Agent 2: MixerArchitect

## Role
MixerProvider, channels, inserts, routing, bus, fader math, mixing console UI.

## File Ownership (~40 files)

### Providers
- `flutter_ui/lib/providers/mixer_provider.dart`
- `flutter_ui/lib/providers/mixer_dsp_provider.dart`

### Widgets
- `flutter_ui/lib/widgets/lower_zone/daw/mix/` (all)
- `flutter_ui/lib/widgets/channel_inspector/` (all)
- `flutter_ui/lib/widgets/mixer/` (19 files) — ultimate_mixer, pro_mixer_strip, VCA strip, channel strip, control room, group manager, plugin selector, floating mixer/send windows, automation badges, IO selectors, color pickers
- `flutter_ui/lib/widgets/routing/` (5 files) — routing matrix standard + advanced, audio graph viz, stem routing matrix
- `flutter_ui/lib/widgets/channel/` (1 file)

### Other
- `flutter_ui/lib/screens/engine_connected_layout.dart` (mixer section)
- `flutter_ui/lib/models/audio_math.dart`
- `flutter_ui/lib/services/session_template_service.dart`

## Critical Rules
1. OutputBus: `.engineIndex`, NEVER `.index` for FFI
2. Modern methods: `setChannelVolume()`, `toggleChannelMute()`, `toggleChannelSolo()`
3. `FaderCurve` in `audio_math.dart` = single source of truth
4. Stereo dual pan: `pan=-1.0` = hard-left (NOT bug), `panRight=+1.0` = hard-right
5. Dual insert state: MixerProvider + _busInserts + Rust — must stay synchronized
6. Master has 8 pre-fader slots, regular channels have 4
7. MixerProvider is SINGLE source of truth → propagate to _busInserts and Rust

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 4 | CRITICAL | OutputBus.index vs .engineIndex | session_template_service.dart:47,58 |
| 6 | CRITICAL | replaceAll ID parsing | mixer_provider.dart |
| 10 | HIGH | Post-fader insert hardcoded < 4 | mixer_provider.dart:2842,2857 |
| 11 | HIGH | Default bus volumes all 1.0 | mixer_dsp_provider.dart:185-191 |
| 20 | MEDIUM | Dual insert 3 sources of truth | engine_connected_layout.dart |
| 36 | HIGH | VCA Trim not synced | vca_strip.dart:32-33 |
| 37 | HIGH | Routing no feedback detection | routing_matrix_panel.dart:190-207 |
| 44 | MEDIUM | Floating window timer | floating_mixer_window.dart:194-201 |
| 71-76 | MEDIUM | IO selector, group manager, automation badge, stem routing, send pan, control room | Various |

## Forbidden
- NEVER use .index for OutputBus FFI — always .engineIndex
- NEVER hardcode insert slot counts
- NEVER parse IDs with replaceAll — use RegExp(r'\d+').firstMatch()
