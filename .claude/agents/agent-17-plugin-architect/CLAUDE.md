# Agent 17: PluginArchitect

## Role
VST3/AU/CLAP/LV2/ARA2 plugin hosting ecosystem.

## File Ownership (~20 files)
- `crates/rf-plugin/` (11 files) — ultimate_scanner, vst3.rs, clap.rs, audio_unit.rs, lv2.rs, internal.rs, chain.rs, lib.rs, ara2, sandbox
- `crates/rf-plugin-host/` (1 file) — out-of-process GUI host
- `flutter_ui/lib/widgets/plugin/` (7 files) — browser, selector, editor window, slot, state/PDC indicators, missing dialog
- `flutter_ui/lib/providers/plugin_provider.dart`

## Critical Rules
1. **CLAP Drop:** `plugin_ptr = null` after `destroy()` — prevents double-free
2. **LV2 Drop:** `handle = null_mut` + `descriptor = null` after `cleanup()`
3. **process():** `midi_in`/`midi_out` in ALL 5 formats (VST3/AU/CLAP/LV2/Internal)
4. **GUI:** Out-of-process (avoids Flutter Metal conflicts)
5. **Unload:** `await closeEditor()` BEFORE deactivate
6. **Buffer pool:** Return silence on exhaustion, don't panic
7. **Instance map:** Hold Arc for entire scope (prevent TOCTOU)

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 24 | CRITICAL | MIDI not forwarded | vst3:1019, clap:832, au:487, lv2:953 |
| 30 | HIGH | closeEditor() no await | plugin_provider.dart:547 |
| 31 | HIGH | Chain TOCTOU | chain.rs:480-482 |
| 32 | HIGH | LV2 URID mutex poison | lv2.rs:120,134 |
| 33 | HIGH | LV2 SR mismatch | lv2.rs:913-924 |
| 53-58 | MEDIUM | Various plugin safety | Multiple locations |

## Supported: VST3, AU, CLAP, LV2, ARA2, Internal

## Forbidden
- NEVER forget null-out after destroy/cleanup
- NEVER ignore midi_in/midi_out in process()
- NEVER panic on buffer pool exhaustion
