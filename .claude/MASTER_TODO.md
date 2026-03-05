# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-05

## Status: ALL COMPLETE — 208/208 + P-USL + P5-CLEAN

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

Analyzer: 0 errors, 0 warnings

---

## NEXT: Stage/Event System Consolidation

### 1. Migrate stage_config.dart consumers to stage_configuration_service.dart
**Priority:** Medium | **Files:** 6

`stage_config.dart` (legacy UI config, 14-value StageCategory) is superseded by
`stage_configuration_service.dart` (active UI config, 11-value StageCategory with `symbol`, `hold`).

Migrate these 6 files that still import stage_config.dart:
- [ ] `services/audio_suggestion_service.dart` — uses StageCategory enum directly
- [ ] `widgets/slot_lab/stage_color_picker.dart` — uses StageCategory enum directly
- [ ] `widgets/slot_lab/stage_occurrence_stats.dart` — uses StageCategory enum directly
- [ ] `widgets/slot_lab/stage_trace_widget.dart` — uses StageConfig.instance only
- [ ] `widgets/slot_lab/stage_analytics_panel.dart` — uses StageConfig.instance only
- [ ] `widgets/slot_lab/stage_trace_comparator.dart` — uses StageConfig.instance only
- [ ] Delete `config/stage_config.dart` after migration

### 2. Rename stage_models.dart StageCategory
**Priority:** Low | **Impact:** Internal only

`stage_models.dart` has a `StageCategory` enum (10 values: spinLifecycle, anticipation, winLifecycle...)
used only in sealed Stage class hierarchy. No external files reference it by name.
Rename to `StageDomainCategory` for clarity (avoids confusion with UI-level StageCategory).

### 3. Three StageCategory enums — current state
| File | Values | Usage |
|------|--------|-------|
| `models/stage_models.dart` | 10 (spinLifecycle, anticipation, winLifecycle, feature, cascade, bonus, gamble, jackpot, ui, special) | Sealed Stage hierarchy |
| `config/stage_config.dart` | 14 (spin, anticipation, win, rollup, bigwin, feature, cascade, jackpot, bonus, gamble, music, ui, system, custom) | Legacy UI config — 6 consumers |
| `services/stage_configuration_service.dart` | 11 (spin, win, feature, cascade, jackpot, hold, gamble, ui, music, symbol, custom) | Active UI config — 27 consumers |

No compile conflicts (never imported together). Task #1 eliminates stage_config.dart.
