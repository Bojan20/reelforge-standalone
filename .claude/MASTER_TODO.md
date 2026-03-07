# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-05

## Status: ALL COMPLETE — 208/208 + P-USL + P5-CLEAN + P5-CONSOLIDATION + P5-WINTIER-UI

## Recent: P5 Win Tier Config UI + QA Fixes

### Win Tier Config Panel (CONFIG tab, right panel)
- **New file:** `widgets/slot_lab/win_tier_config_panel.dart`
- Regular win tier editor: multiplier ranges, labels, rollup durations, tick rates
- Big win tier editor: thresholds, labels, intensities (visual/particle/audio), celebration durations
- Preset selector: Standard, High Volatility, Jackpot Focus, Mobile
- JSON import/export, Reset, Validation display
- `SlotWinConfiguration.getWinTierResult()` method added to model

### Hardcoded Threshold Elimination
- COIN_SHOWER_START: `>= 20` → `isBigWin` (from P5 config)
- Legacy fallbacks: replaced with `SlotWinConfiguration.defaultConfig().getWinTierResult()`
- `_getWinTierFromRatio()`: replaced hardcoded thresholds with P5 config lookup
- Zero hardcoded win tier values remain in widget code

### FS Flow Fix (deferred game flow evaluation)
- `flushGameFlowResult()` at 6 correct exit points in slot_preview_widget
- SCATTER_WIN audio + 1.2s delay before FS plaketa
- SCATTER_COLLECT → SCATTER_WIN rename (all files)

### QA Audit Results (P0-P3)
- **P0:** Audio thread allocs/locks in playback.rs (architectural — future refactor)
- **P1 FIXED:** Win tier hardcoding eliminated
- **P1 VERIFIED:** HardwareKeyboard.instance — all 100+ usages are in valid contexts (Listener/keyboard handlers)
- **P2 FIXED:** OutputBus.index (already clean), MixerProvider old methods (setVolume→setChannelVolume, setPan→setChannelPan)
- **P2 VERIFIED:** engine_api.dart print() — already clean (0 instances)
- **P2 FIXED:** unnecessary_underscores lint in slot_preview_widget, symbol_art_panel

| System | Tasks | Status |
|--------|-------|--------|
| AUREXIS | 88/88 | Done |
| SlotLab Middleware Providers | 19/19 | Done |
| Core Systems (P-SRC..P-SSS) | 129/129 | Done |
| P-FMC FluxMacro (6 phases) | 53/53 | Done |
| P-ICF Intensity Crossfade | 8/8 | Done |
| P-RTE Recursive Trigger | 5/5 | Done |
| P-CTR Conflict Resolution | 5/5 | Done |
| P-PPL Publish Pipeline | 8/8 | Done |
| P-USL Unified SlotLab | Done | Done |
| P5 Win Tier Naming | Done | Done |
| P5 Stage Event Cleanup | Done | Done |
| P5 StageCategory Consolidation | Done | Done |

Analyzer: 0 errors, 0 warnings

---

## Completed: StageCategory Consolidation

### What was done:
1. **Unified StageCategory enum** — `stage_config.dart` now imports+re-exports `StageCategory` from `stage_configuration_service.dart` (11 values: spin, win, feature, cascade, jackpot, hold, gamble, ui, music, symbol, custom)
2. **Legacy category mapping** — Removed 5 legacy categories: anticipation→spin, rollup→win, bigwin→win, bonus→feature, system→ui
3. **Migrated all 6 consumer files** — audio_suggestion_service, stage_color_picker, stage_occurrence_stats, stage_trace_widget, stage_analytics_panel, stage_trace_comparator
4. **Renamed stage_models.dart StageCategory → StageDomainCategory** — Domain-level enum (10 values: spinLifecycle, anticipation, winLifecycle, etc.) now has distinct name, no confusion with UI-level StageCategory
5. **Updated tests** — stage_trace_widget_test.dart, event_registry_slotlab_test.dart

### Two StageCategory enums — final state
| File | Enum Name | Values | Usage |
|------|-----------|--------|-------|
| `models/stage_models.dart` | `StageDomainCategory` | 10 (spinLifecycle, anticipation, winLifecycle...) | Sealed Stage hierarchy |
| `services/stage_configuration_service.dart` | `StageCategory` | 11 (spin, win, feature, cascade, jackpot, hold, gamble, ui, music, symbol, custom) | SSoT for UI — re-exported via stage_config.dart |

`config/stage_config.dart` remains as visual layer (per-stage colors, icons, high contrast mode) but no longer has its own enum.
