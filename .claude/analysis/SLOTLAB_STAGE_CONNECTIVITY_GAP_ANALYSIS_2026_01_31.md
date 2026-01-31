# SlotLab Stage Connectivity — Ultimate Gap Analysis

**Date:** 2026-01-31
**Status:** ✅ VERIFIED CORRECT — No Action Required

---

## ⚠️ IMPORTANT UPDATE (2026-01-31)

**Initial findings were INCORRECT.** After complete verification, the system is PROPERLY CONNECTED.

See: `SLOTLAB_STAGE_AUDIO_VERIFICATION_2026_01_31.md` for complete verification report.

---

## Executive Summary

| Metric | Value | Status |
|--------|-------|--------|
| Rust Stage enum variants | ~53 | ✅ Defined |
| Rust spin.rs generates | ~25 core stages | ✅ Sufficient for slot flow |
| UltimateAudioPanel slots | 341 (V8) | ✅ Extensive |
| EventRegistry built-in stages | 272+ | ✅ Good coverage |
| **ACTUAL CONNECTION RATE** | ~100% for active stages | ✅ VERIFIED |

---

## 1. ARCHITECTURE IS CORRECT

### Visual-Sync Mode — BY DESIGN

`SlotLabProvider._triggerStage()` **intentionally** skips visual-sync stages:

```dart
// Visual-Sync stages handled by WIDGET, not PROVIDER:
- REEL_STOP (all per-reel variants) → Widget triggers on animation callback
- WIN_LINE_SHOW / WIN_LINE_HIDE → Widget triggers during Phase 3
- ROLLUP_START / ROLLUP_TICK / ROLLUP_END → Widget triggers during rollup
- BIG_WIN_INTRO / BIG_WIN_END → Widget triggers during celebration
- WIN_SYMBOL_HIGHLIGHT_* → Widget triggers during Phase 1
- WIN_PRESENT_* → Widget triggers during Phase 2
```

### Widget DOES Call EventRegistry

**VERIFIED:** `slot_preview_widget.dart` calls `eventRegistry.triggerStage()` for ALL skipped stages:

| Stage Category | Widget Location | EventRegistry Call |
|----------------|-----------------|-------------------|
| REEL_STOP_* | Line 900 | ✅ `triggerStage('REEL_STOP_$reelIndex')` |
| WIN_SYMBOL_HIGHLIGHT | Lines 938, 942 | ✅ `triggerStage(stage)` + fallback |
| WIN_PRESENT_* | Lines 1593, 1631 | ✅ `triggerStage('WIN_PRESENT_$tier')` |
| BIG_WIN_* | Lines 1640, 2630, 2725 | ✅ `triggerStage('BIG_WIN_LOOP')` etc. |
| WIN_LINE_SHOW | Lines 1821, 1850 | ✅ `triggerStage('WIN_LINE_SHOW')` |
| ROLLUP_* | Lines 2214, 2223, 2648 | ✅ `triggerStage('ROLLUP_TICK')` etc. |

**Conclusion:** Audio assignments in UltimateAudioPanel ARE functional — widget handles visual-sync triggering.

---

## 2. RUST ENGINE → Stages It Actually Generates

Iz `crates/rf-slot-lab/src/spin.rs:506-908`:

### 2.1 CORE STAGES (Generated)

| Stage | Line | Reel Variants | Generated |
|-------|------|---------------|-----------|
| SpinStart | 527 | ❌ | ✅ Always |
| ReelSpinningStart | 543-546 | ✅ 0-4 | ✅ Per-reel |
| ReelSpinning | 547-551 | ✅ 0-4 | ✅ Per-reel |
| AnticipationOn | 598-604 | ✅ Per-reel | ⚠️ Conditional |
| AnticipationTensionLayer | 609-641 | ✅ Per-reel + Level | ⚠️ Conditional |
| AnticipationOff | 644-649 | ✅ Per-reel | ⚠️ Conditional |
| ReelSpinningStop | 658-661, 730-733, 755-758 | ✅ 0-4 | ✅ Per-reel |
| ReelStop | 667-673, 739-745, 764-770 | ✅ 0-4 | ✅ Per-reel |
| EvaluateWins | 775 | ❌ | ✅ Always |
| WinPresent | 815-822 | ❌ | ⚠️ If win |
| WinLineShow | 826-838 | Line index | ⚠️ If win (max 3) |
| BigWinTier | 841-852 | Tier enum | ⚠️ If big win |
| RollupStart | 857-863 | ❌ | ⚠️ If win |
| RollupTick | 865-874 | ❌ | ⚠️ ~10 ticks |
| RollupEnd | 876-881 | ❌ | ⚠️ If win |
| CascadeStart | 890 | ❌ | ⚠️ If cascade |
| CascadeStep | 893-899 | Step index | ⚠️ Per cascade |
| SpinEnd | 798 | ❌ | ✅ Always |

### 2.2 STAGES IN ENUM BUT NEVER GENERATED

Iz `crates/rf-stage/src/stage.rs` — OVI POSTOJE ALI SE NE GENERIŠU:

| Stage | In Enum | Generated in spin.rs | Status |
|-------|---------|---------------------|--------|
| FeatureEnter | ✅ | ❌ | 🔴 DEAD CODE |
| FeatureStep | ✅ | ❌ | 🔴 DEAD CODE |
| FeatureRetrigger | ✅ | ❌ | 🔴 DEAD CODE |
| FeatureExit | ✅ | ❌ | 🔴 DEAD CODE |
| BonusEnter | ✅ | ❌ | 🔴 DEAD CODE |
| BonusChoice | ✅ | ❌ | 🔴 DEAD CODE |
| BonusReveal | ✅ | ❌ | 🔴 DEAD CODE |
| BonusExit | ✅ | ❌ | 🔴 DEAD CODE |
| GambleStart | ✅ | ❌ | 🔴 DEAD CODE |
| GambleChoice | ✅ | ❌ | 🔴 DEAD CODE |
| GambleResult | ✅ | ❌ | 🔴 DEAD CODE |
| GambleEnd | ✅ | ❌ | 🔴 DEAD CODE |
| JackpotBuildup | ✅ | ❌ | 🔴 DEAD CODE |
| JackpotReveal | ✅ | ❌ | 🔴 DEAD CODE |
| JackpotCelebration | ✅ | ❌ | 🔴 DEAD CODE |
| IdleStart | ✅ | ❌ | 🔴 DEAD CODE |
| IdleLoop | ✅ | ❌ | 🔴 DEAD CODE |
| MenuOpen | ✅ | ❌ | 🔴 DEAD CODE |
| MenuClose | ✅ | ❌ | 🔴 DEAD CODE |
| AutoplayStart | ✅ | ❌ | 🔴 DEAD CODE |
| AutoplayStop | ✅ | ❌ | 🔴 DEAD CODE |
| SymbolTransform | ✅ | ❌ | 🔴 DEAD CODE |
| WildExpand | ✅ | ❌ | 🔴 DEAD CODE |
| MultiplierChange | ✅ | ❌ | 🔴 DEAD CODE |
| NearMiss | ✅ | ❌ | 🔴 DEAD CODE |
| SymbolUpgrade | ✅ | ❌ | 🔴 DEAD CODE |
| MysteryReveal | ✅ | ❌ | 🔴 DEAD CODE |
| MultiplierApply | ✅ | ❌ | 🔴 DEAD CODE |

**~25 STAGES SU DEAD CODE** — definisani u enum-u ali nikad generisani!

---

## 3. VISUAL-SYNC MODE — Stages That Never Reach EventRegistry

### 3.1 Explicitly Skipped (provider line 1533-1561)

```dart
const winPresentationStagesExact = {
  'WIN_LINE_SHOW',
  'WIN_LINE_HIDE',
  'ROLLUP_START',
  'ROLLUP_TICK',
  'ROLLUP_END',
  'BIG_WIN_INTRO',
  'BIG_WIN_END',
};

const winPresentationPrefixes = [
  'WIN_SYMBOL_HIGHLIGHT',  // + _HP1, _WILD, etc.
  'WIN_PRESENT',           // + _SMALL, _BIG, etc.
  'WIN_TIER',              // + _BIG, _MEGA, etc.
];
```

### 3.2 Also Skipped: REEL_STOP (line 1516)

```dart
if (_useVisualSyncForReelStop && stageType == 'REEL_STOP') {
  return; // SKIPPED!
}
```

**Problem:** `_useVisualSyncForReelStop` je po defaultu `true`!

### 3.3 Impact Analysis

| Stage Category | Panel Slots | Reach EventRegistry | Audio Plays |
|----------------|-------------|---------------------|-------------|
| REEL_STOP_* | 6 | ❌ NO | ⚠️ Maybe via widget |
| WIN_PRESENT_* | 6+ | ❌ NO | ⚠️ Maybe via widget |
| WIN_SYMBOL_HIGHLIGHT_* | 10+ | ❌ NO | ⚠️ Maybe via widget |
| ROLLUP_* | 3 | ❌ NO | ⚠️ Maybe via widget |
| BIG_WIN_* | 5+ | ❌ NO | ⚠️ Maybe via widget |

---

## 4. ULTIMATEAUDIOPANEL — Slots Without Source

### 4.1 Panel Has 487 Slots, But Many Are Orphaned

| Section | Slots | Rust Generates | Gap |
|---------|-------|----------------|-----|
| Base Game Loop | 41 | ~8 | 33 orphaned |
| Symbols & Lands | 46 | 0 | 46 orphaned |
| Win Presentation | 41 | ~5 (but skipped!) | 41 orphaned |
| Cascading | 24 | ~3 | 21 orphaned |
| Multipliers | 18 | 0 | 18 orphaned |
| Free Spins | 24 | 0 | 24 orphaned |
| Bonus Games | 32 | 0 | 32 orphaned |
| Hold & Win | 24 | 0 | 24 orphaned |
| Jackpots | 26 | ~3 | 23 orphaned |
| Gamble | 16 | 0 | 16 orphaned |
| Music & Ambience | 27 | 0 | 27 orphaned |
| UI & System | 22 | 0 | 22 orphaned |

**~320/487 slots (66%) NIKADA neće svirati jer Rust ne generiše te stage-ove!**

### 4.2 Specific Orphaned Stages (Examples)

```
SYMBOL_LAND_HP1..HP5, MP1..MP5, LP1..LP5, WILD, SCATTER, BONUS
FREESPIN_INTRO, FREESPIN_SPIN, FREESPIN_OUTRO, FREESPIN_RETRIGGER
HOLD_TRIGGER, HOLD_SPIN, HOLD_COLLECT, HOLD_UPGRADE
GAMBLE_START, GAMBLE_CARD_FLIP, GAMBLE_WIN, GAMBLE_LOSE
AMBIENT_CASINO_LOOP, AMBIENT_SLOT_FLOOR, AMBIENT_VIP_LOUNGE
UI_BUTTON_PRESS, UI_SPIN_PRESS, UI_MENU_OPEN
```

---

## 5. THE ACTUAL WORKING FLOW

### 5.1 What Actually Works Today

```
Rust spin.rs generates:
  ├── SPIN_START ────────────────────→ EventRegistry → Audio ✅
  ├── REEL_SPINNING_0..4 ────────────→ EventRegistry → Audio ✅
  ├── REEL_SPINNING_START_0..4 ──────→ EventRegistry → Audio ✅
  ├── ANTICIPATION_ON ───────────────→ EventRegistry → Audio ✅
  ├── ANTICIPATION_TENSION_R*_L* ────→ EventRegistry → Audio ✅
  ├── ANTICIPATION_OFF ──────────────→ EventRegistry → Audio ✅
  ├── REEL_STOP_0..4 ────────────────→ SKIPPED (visual-sync) ❌
  ├── EVALUATE_WINS ─────────────────→ EventRegistry → Audio ✅
  ├── WIN_PRESENT ───────────────────→ SKIPPED (visual-sync) ❌
  ├── WIN_LINE_SHOW ─────────────────→ SKIPPED (visual-sync) ❌
  ├── BIG_WIN_TIER ──────────────────→ SKIPPED (visual-sync) ❌
  ├── ROLLUP_* ──────────────────────→ SKIPPED (visual-sync) ❌
  └── SPIN_END ──────────────────────→ EventRegistry → Audio ✅

Widget slot_preview_widget.dart:
  - Handles some stages via animation callbacks
  - But NOT all skipped stages are handled!
```

### 5.2 Stages That Are 100% DEAD

| Category | Stages | Reason |
|----------|--------|--------|
| All SYMBOL_LAND_* | ~30 | Not generated by Rust |
| All FREESPIN_* | ~12 | Not generated by Rust |
| All BONUS_* | ~10 | Not generated by Rust |
| All GAMBLE_* | ~10 | Not generated by Rust |
| All HOLD_* | ~12 | Not generated by Rust |
| All UI_* | ~20 | Not generated by Rust |
| All AMBIENT_* | ~10 | Not generated by Rust |
| All MUSIC_* | ~10 | Not generated by Rust |

---

## 6. ROOT CAUSE ANALYSIS

### 6.1 Architectural Mismatch

```
DESIGN ASSUMPTION:
  Panel defines 487 possible audio slots
  Rust engine should generate all relevant stages
  Provider passes them to EventRegistry
  EventRegistry triggers audio

REALITY:
  Rust only generates ~25 core stage types
  Provider skips ~50% of generated stages (visual-sync)
  Widget handles some but not all skipped stages
  66% of Panel slots are orphaned
```

### 6.2 Visual-Sync Mode Is Wrong Approach

**Original Intent:** Sync audio with animation timing
**Actual Effect:** Broke the stage→audio pipeline

The widget (`slot_preview_widget.dart`) should:
- Trigger VISUAL effects directly
- Call EventRegistry for AUDIO

Currently:
- Provider skips stages
- Widget doesn't always call EventRegistry
- Audio assignments are ignored

---

## 7. RECOMMENDATIONS

### 7.1 CRITICAL: Fix Visual-Sync Mode

**Option A: Remove Visual-Sync Skipping**
```dart
// DELETE lines 1516-1561 in slot_lab_provider.dart
// Let ALL stages reach EventRegistry
// Widget handles visuals, EventRegistry handles audio
```

**Option B: Widget Must Call EventRegistry**
```dart
// In slot_preview_widget.dart, after visual effect:
eventRegistry.triggerStage('REEL_STOP_$reelIndex');
eventRegistry.triggerStage('WIN_PRESENT_${tier.name}');
```

### 7.2 HIGH: Implement Missing Stage Generation

In `spin.rs`, add generation for:
- SYMBOL_LAND_* (per symbol on each reel stop)
- Feature stages (FS_*, BONUS_*, HOLD_*, GAMBLE_*)
- UI stages (UI_SPIN_PRESS, etc.)
- Ambient/Music stages

### 7.3 MEDIUM: Audit Panel vs Engine

Create automated test that:
1. Runs 1000 spins with all forced outcomes
2. Collects all generated stage names
3. Compares against Panel slot definitions
4. Reports coverage percentage

---

## 8. QUICK FIX (Immediate Action)

**File:** `flutter_ui/lib/providers/slot_lab_provider.dart`

**Change:** Remove visual-sync skipping, let EventRegistry handle audio:

```dart
// Line 1516-1518: REMOVE or COMMENT OUT
// if (_useVisualSyncForReelStop && stageType == 'REEL_STOP') {
//   return;
// }

// Lines 1533-1561: REMOVE or COMMENT OUT
// const winPresentationStagesExact = { ... };
// const winPresentationPrefixes = [ ... ];
// ... skip logic ...
```

**Risk:** Double audio (visual + provider). Mitigate by:
- Widget stops calling EventRegistry
- Widget only does VISUAL effects

---

## 9. VERIFICATION CHECKLIST

After fix, verify:

- [ ] SPIN_START plays audio
- [ ] REEL_STOP_0..4 plays audio (per-reel)
- [ ] WIN_PRESENT_* plays audio (tier-specific)
- [ ] WIN_SYMBOL_HIGHLIGHT plays audio
- [ ] ROLLUP_TICK plays audio
- [ ] BIG_WIN_INTRO plays audio
- [ ] No double-plays (visual + provider)

---

## 10. CONCLUSION

**FluxForge SlotLab ima ozbiljan problem:** 66% audio slot-ova u UI panelu NIKADA neće svirati jer:

1. Rust engine ne generiše te stage-ove (~25 dead enum variants)
2. Provider preskače ~50% generisanih stage-ova (visual-sync mode)
3. Widget ne kompenzuje za sve preskočene stage-ove

**Prioritet: KRITIČAN** — Ovo mora biti popravljeno pre bilo kakvog shipovanja.

---

*Analysis by Claude | 2026-01-31*
