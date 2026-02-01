# P13 — Feature Builder Final Push

**Date:** 2026-02-01
**Status:** 🔨 75% Complete (55/73 tasks) → Target: 100%
**Remaining:** 13 tasks, ~1,250 LOC, ~8 hours (1-2 days)

---

## 🎯 OBJECTIVE

Complete Feature Builder panel to 100% production-ready state.

**What It Does:**
- Visual block-based slot game configuration
- 18 feature blocks (Core, Features, Bonus, Presentation)
- Dependency resolution (auto-enable required blocks)
- Validation (error/warning/info rules)
- 16 built-in presets
- Apply & Build → instant slot machine

---

## 📋 REMAINING TASKS (13)

### P13.8 — Apply & Build Testing (4 tasks)

**P13.8.6 — UltimateAudioPanel Stage Registration**
```yaml
LOC: ~100
ETA: 30 minutes
File: flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart

Task:
  - Add generatedStages parameter
  - Create _FeatureBuilderSection class
  - Display generated stages in FIRST section
  - Group by category (free_spins, bonus, cascade, etc.)
  - Mark pooled (⚡) and looping (🔄) stages

Integration:
  - slot_lab_screen.dart: Consumer2 (add FeatureBuilderProvider)
  - Pass generatedStages to UltimateAudioPanel
```

**P13.8.7 — ForcedOutcomePanel Dynamic Controls**
```yaml
LOC: ~100
ETA: 30 minutes
File: flutter_ui/lib/widgets/slot_lab/forced_outcome_panel.dart

Task:
  - Show/hide buttons based on FeatureBuilderProvider state
  - if (isBlockEnabled('free_spins')) → show "Force FS" button
  - if (isBlockEnabled('hold_and_win')) → show "Force H&W" button

Blocks → Outcomes:
  - Free Spins → ForcedOutcome.freeSpins
  - Hold & Win → ForcedOutcome.holdAndWin
  - Bonus Game → ForcedOutcome.bonus
  - Jackpot → ForcedOutcome.jackpotGrand
  - Cascade → ForcedOutcome.cascade
```

**P13.8.8 — Unit Tests (30+)**
```yaml
LOC: ~150
ETA: 1 hour
Files: test/feature_builder/*.dart

Tests:
  - block_generation_test.dart: Test each block generates correct stages
  - validation_test.dart: Test error/warning rules (scatter required, etc.)
  - serialization_test.dart: Test preset toJson/fromJson + version migration

Coverage:
  - 10 blocks × 2 tests each = 20 tests
  - 10 validation rules = 10 tests
  - Total: 30+ tests
```

**P13.8.9 — Integration Tests (10)**
```yaml
LOC: ~50
ETA: 30 minutes
Files: test/feature_builder/integration/*.dart

Tests:
  - apply_flow_test.dart: Full Apply & Build flow
  - preset_load_test.dart: Load built-in presets, verify dependencies
  - grid_update_test.dart: Verify slot machine updates correctly

Coverage: 10 end-to-end scenarios
```

---

### P13.9 — Additional Blocks (5 tasks)

**P13.9.1 — AnticipationBlock**
```yaml
LOC: ~300
ETA: 2 hours
File: flutter_ui/lib/blocks/anticipation_block.dart

Options:
  - Pattern: "Tip A" (2+ scatters) / "Tip B" (Near miss)
  - Trigger Symbol: Scatter / Bonus / Wild
  - Tension Escalation: L1-L4 levels
  - Visual Effect: Glow / Pulse / Flash
  - Audio Profile: Subtle / Moderate / Dramatic

Generated Stages:
  - ANTICIPATION_ON
  - ANTICIPATION_TENSION_R{1-4}_L{1-4}
  - ANTICIPATION_OFF
  - NEAR_MISS_REEL_{0-4}

Dependencies:
  - Requires: Scatter OR Bonus symbol
  - Modifies: Reel timing
```

**P13.9.5 — WildFeaturesBlock**
```yaml
LOC: ~350
ETA: 2 hours
File: flutter_ui/lib/blocks/wild_features_block.dart

Options:
  - Expansion: Disabled / Full Reel / Cross Pattern
  - Sticky Duration: 1-10 spins
  - Walking Direction: Left / Right / Random / Bidirectional
  - Multiplier Range: 1x-10x
  - Stack Height: 2-7 symbols

Generated Stages:
  - WILD_LAND
  - WILD_EXPAND_START / WILD_EXPAND_COMPLETE
  - WILD_STICK_APPLY / WILD_STICK_PERSIST
  - WILD_WALK_MOVE / WILD_WALK_ARRIVE
  - WILD_MULT_APPLY (×2, ×3, ×5, ×10)
  - WILD_STACK_FORM (2-stack, 3-stack, etc.)

Dependencies:
  - Requires: Wild symbol
  - Modifies: Win evaluation
```

**P13.9.8 — Update Dependency Matrix**
```yaml
LOC: ~100
ETA: 30 minutes
File: services/feature_builder/dependency_resolver.dart

Task:
  - Add AnticipationBlock dependencies
  - Add WildFeaturesBlock dependencies
  - Verify no circular dependencies
```

**P13.9.9 — Additional Presets (6)**
```yaml
LOC: ~100
ETA: 30 minutes
File: data/feature_builder/built_in_presets.dart

New Presets:
  13. Anticipation Focus — Core + FS + Anticipation + WinPres
  14. Wild Heavy — Core + FS + WildFeatures + WinPres
  15. Bonus Heavy — Core + BonusGame + Multiplier + WinPres
  16. Multiplier Focus — Core + Cascades + Multiplier + WinPres
  17. Jackpot Focus — Core + Jackpot + HoldWin + WinPres
  18. Full Feature Ultra — ALL 18 blocks enabled
```

---

## 🚀 EXECUTION STRATEGY

### Parallel Opus Execution (Recommended)

**Agent 1:** P13.8.6 + P13.8.7 (UI integration, ~200 LOC, 1 hour)
**Agent 2:** P13.9.1 AnticipationBlock (~300 LOC, 2 hours)
**Agent 3:** P13.9.5 WildFeaturesBlock (~350 LOC, 2 hours)

**Sequential:** P13.8.8, P13.8.9, P13.9.8, P13.9.9 (tests + cleanup, ~400 LOC, 2 hours)

**Total Time:** ~4 hours (with parallelization)

### Sequential Execution (Alternative)

1. UI Integration (P13.8.6-7) — 1 hour
2. Blocks (P13.9.1, P13.9.5) — 4 hours
3. Tests (P13.8.8-9) — 1.5 hours
4. Cleanup (P13.9.8-9) — 1 hour

**Total Time:** ~7.5 hours (1 working day)

---

## ✅ ACCEPTANCE CRITERIA

**Functional:**
- ✅ All 18 blocks implemented
- ✅ Apply & Build generates slot machine
- ✅ Dependency resolution works
- ✅ Validation catches errors
- ✅ 16 presets load correctly

**Quality:**
- ✅ flutter analyze = 0 errors
- ✅ 40+ tests passing (30 unit + 10 integration)
- ✅ All features documented

**User Experience:**
- ✅ Click block → configure options → Apply → instant slot
- ✅ Load preset → auto-enable dependencies
- ✅ Validation errors → clear messages + fix suggestions

---

## 📊 IMPACT

**Once Complete:**
- Feature Builder: 100% (73/73 tasks)
- Overall Project: 76% (284/362 tasks)
- User-facing feature ready for production

---

**Ready to execute?** Start with parallel Opus agents for maximum speed.

*Task Plan: 2026-02-01*
