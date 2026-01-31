# Win Tier System Specification

**Version:** 2.0
**Date:** 2026-01-31
**Status:** ✅ APPROVED — Ready for implementation

---

## 1. Overview

Fleksibilan, data-driven sistem za definisanje win tier-ova u slot igrama. Umesto hardkodiranih naziva (SMALL_WIN, BIG_WIN, MEGA_WIN...), koristi se numerička nomenklatura (WIN_1, WIN_2, WIN_3...) sa konfigurisanim opsezima.

---

## 2. Naming Convention

### Stage Names
```
WIN_1, WIN_2, WIN_3, WIN_4, WIN_5, WIN_6, ...
```

### Audio Event Names
```
WIN_PRESENT_1, WIN_PRESENT_2, WIN_PRESENT_3, ...
ROLLUP_1, ROLLUP_2, ROLLUP_3, ...
```

### Display Labels (Configurable)
```
WIN_1 → "WIN!"
WIN_2 → "NICE WIN!"
WIN_3 → "BIG WIN!"
WIN_4 → "MEGA WIN!"
WIN_5 → "EPIC WIN!"
WIN_6 → "ULTRA WIN!"
```

**Note:** Display labels are separate from tier IDs and fully configurable.

---

## 3. Data Model

### WinTierDefinition

```dart
class WinTierDefinition {
  /// Tier ID (1, 2, 3, ...)
  final int tierId;

  /// Stage name generated from ID: "WIN_1", "WIN_2", etc.
  String get stageName => 'WIN_$tierId';

  /// Multiplier range: from X times bet TO Y times bet
  final double fromMultiplier;  // inclusive
  final double toMultiplier;    // exclusive (except last tier = infinity)

  /// Display label shown in win plaque
  final String displayLabel;

  /// Rollup duration in milliseconds
  final int rollupDurationMs;

  /// Rollup tick rate (ticks per second)
  final int rollupTickRate;

  /// Optional: Custom color for this tier
  final Color? plaqueColor;

  /// Optional: Particle burst count for celebration
  final int particleBurstCount;

  /// Check if win amount falls into this tier
  bool matches(double winAmount, double betAmount) {
    final multiplier = betAmount > 0 ? winAmount / betAmount : 0;
    return multiplier >= fromMultiplier && multiplier < toMultiplier;
  }
}
```

### WinTierConfig

```dart
class WinTierConfig {
  /// Config ID (e.g., "default", "high_volatility", "gdd_imported")
  final String configId;

  /// Display name
  final String name;

  /// List of tier definitions (ordered by fromMultiplier)
  final List<WinTierDefinition> tiers;

  /// Source of this config
  final WinTierConfigSource source;

  /// Get tier for given win/bet
  WinTierDefinition? getTierForWin(double winAmount, double betAmount) {
    for (final tier in tiers) {
      if (tier.matches(winAmount, betAmount)) {
        return tier;
      }
    }
    return null; // No win (below minimum threshold)
  }

  /// Validate config (no gaps, no overlaps)
  bool validate() {
    if (tiers.isEmpty) return false;

    // Sort by fromMultiplier
    final sorted = [...tiers]..sort((a, b) => a.fromMultiplier.compareTo(b.fromMultiplier));

    // Check continuity
    for (int i = 0; i < sorted.length - 1; i++) {
      if (sorted[i].toMultiplier != sorted[i + 1].fromMultiplier) {
        return false; // Gap or overlap detected
      }
    }

    return true;
  }
}

enum WinTierConfigSource {
  builtin,    // Factory default
  gddImport,  // Imported from GDD
  manual,     // Manually configured
  custom,     // Custom preset
}
```

---

## 4. Configuration Sources

### 4.1 GDD Import

When importing a Game Design Document, win tiers can be extracted from:

```json
{
  "winTiers": [
    {
      "id": 1,
      "label": "WIN!",
      "fromBet": 1,
      "toBet": 5
    },
    {
      "id": 2,
      "label": "BIG WIN!",
      "fromBet": 5,
      "toBet": 15
    }
  ]
}
```

**GDD Import Flow:**
1. Parse `winTiers` array from GDD JSON
2. Create `WinTierConfig` with `source: WinTierConfigSource.gddImport`
3. Validate ranges (no gaps, no overlaps)
4. Store in `SlotLabProjectProvider`

### 4.2 Manual Configuration

Users can manually edit tiers through UI:

**UI Elements:**
- Add Tier button
- Remove Tier button (with confirmation)
- Per-tier editors:
  - Display Label (text field)
  - From Multiplier (number input with slider)
  - To Multiplier (number input with slider)
  - Rollup Duration (ms)
  - Rollup Tick Rate
  - Plaque Color (color picker)
  - Particle Count (slider)

**Validation:**
- Ranges must be continuous (no gaps)
- Ranges must not overlap
- At least 1 tier required
- Maximum 10 tiers (reasonable limit)

### 4.3 Presets

Built-in presets for common configurations:

| Preset | Tiers | Description |
|--------|-------|-------------|
| Standard | 6 | Default slot configuration |
| High Volatility | 8 | More granular big win tiers |
| Low Volatility | 4 | Fewer, broader tiers |
| Minimal | 2 | Just "WIN" and "BIG WIN" |

---

## 5. Stage Generation

### Stage Names Generated

For a config with N tiers:

```
WIN_1, WIN_2, WIN_3, ..., WIN_N
WIN_PRESENT_1, WIN_PRESENT_2, ..., WIN_PRESENT_N
ROLLUP_START_1, ROLLUP_START_2, ..., ROLLUP_START_N
ROLLUP_TICK_1, ROLLUP_TICK_2, ..., ROLLUP_TICK_N
ROLLUP_END_1, ROLLUP_END_2, ..., ROLLUP_END_N
```

### Fallback Stages

Generic stages for backward compatibility:

```
WIN_PRESENT → Falls back to tier-specific
ROLLUP_START → Falls back to tier-specific
ROLLUP_TICK → Falls back to tier-specific
ROLLUP_END → Falls back to tier-specific
```

---

## 6. Provider Integration

### SlotLabProjectProvider

```dart
class SlotLabProjectProvider extends ChangeNotifier {
  WinTierConfig _winTierConfig = WinTierConfig.defaultConfig();

  WinTierConfig get winTierConfig => _winTierConfig;

  /// Set config from GDD import
  void setWinTierConfigFromGdd(Map<String, dynamic> gddJson) {
    _winTierConfig = WinTierConfig.fromGddJson(gddJson);
    notifyListeners();
  }

  /// Set config manually
  void setWinTierConfig(WinTierConfig config) {
    if (!config.validate()) {
      throw ArgumentError('Invalid win tier config: gaps or overlaps detected');
    }
    _winTierConfig = config;
    notifyListeners();
  }

  /// Add tier
  void addWinTier(WinTierDefinition tier) { ... }

  /// Update tier
  void updateWinTier(int tierId, WinTierDefinition updated) { ... }

  /// Remove tier
  void removeWinTier(int tierId) { ... }

  /// Get tier for win
  WinTierDefinition? getWinTier(double winAmount, double betAmount) {
    return _winTierConfig.getTierForWin(winAmount, betAmount);
  }
}
```

### EventRegistry Integration

```dart
// In EventRegistry.triggerStage()
void triggerStage(String stage, {Map<String, dynamic>? payload}) {
  // If stage is WIN_PRESENT, determine tier
  if (stage == 'WIN_PRESENT' && payload != null) {
    final winAmount = payload['winAmount'] as double?;
    final betAmount = payload['betAmount'] as double?;

    if (winAmount != null && betAmount != null) {
      final tier = _projectProvider.getWinTier(winAmount, betAmount);
      if (tier != null) {
        // Trigger tier-specific stage
        triggerStage('WIN_PRESENT_${tier.tierId}', payload: payload);
        return;
      }
    }
  }

  // Normal stage processing
  _processStage(stage, payload);
}
```

---

## 7. UI Panel

### Win Tier Editor Panel

Location: SlotLab Lower Zone → Settings tab OR dedicated "Win Tiers" tab

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ WIN TIER CONFIGURATION                          [Preset ▼]  │
├─────────────────────────────────────────────────────────────┤
│ Source: [GDD Import ●] [Manual ○] [Preset ○]                │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ WIN_1  │ "WIN!"      │ 1x - 5x   │ 1500ms │ [Edit] [×] │ │
│ │ WIN_2  │ "NICE WIN!" │ 5x - 10x  │ 2000ms │ [Edit] [×] │ │
│ │ WIN_3  │ "BIG WIN!"  │ 10x - 25x │ 3000ms │ [Edit] [×] │ │
│ │ WIN_4  │ "MEGA WIN!" │ 25x - 50x │ 5000ms │ [Edit] [×] │ │
│ │ WIN_5  │ "EPIC WIN!" │ 50x - 100x│ 8000ms │ [Edit] [×] │ │
│ │ WIN_6  │ "ULTRA WIN!"│ 100x+     │ 12000ms│ [Edit] [×] │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                              [+ Add Tier]   │
├─────────────────────────────────────────────────────────────┤
│ ⚠️ Validation: OK (no gaps, no overlaps)                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Migration Plan

### Files to Update

1. **Models:**
   - `flutter_ui/lib/models/win_tier_config.dart` — NEW
   - `flutter_ui/lib/models/slot_lab_models.dart` — Add WinTierConfig reference

2. **Providers:**
   - `flutter_ui/lib/providers/slot_lab_project_provider.dart` — Add win tier management
   - `flutter_ui/lib/services/event_registry.dart` — Tier-based stage resolution

3. **UI:**
   - `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` — Use tier config
   - `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` — Use tier config
   - `flutter_ui/lib/widgets/slot_lab/win_tier_editor_panel.dart` — NEW

4. **GDD Import:**
   - `flutter_ui/lib/services/gdd_import_service.dart` — Parse win tiers

5. **Rust Engine:**
   - `crates/rf-slot-lab/src/spin.rs` — Configurable tier thresholds
   - `crates/rf-stage/src/lib.rs` — Dynamic stage enum or string-based

### Backward Compatibility

Old code using hardcoded names will continue to work through fallback mapping:

```dart
const _legacyStageMapping = {
  'SMALL_WIN': 'WIN_1',
  'BIG_WIN': 'WIN_3',
  'MEGA_WIN': 'WIN_4',
  'EPIC_WIN': 'WIN_5',
  'ULTRA_WIN': 'WIN_6',
  'WIN_PRESENT_SMALL': 'WIN_PRESENT_1',
  'WIN_PRESENT_BIG': 'WIN_PRESENT_3',
  // etc.
};
```

---

## 9. Default Values — Standard Win Tiers

### 9.1 Regular Win Tiers (WIN_LOW through WIN_6)

| Tier ID | Stage Name | Opseg (× bet) | Kategorija | Display Label | Audio Intent |
|---------|------------|---------------|------------|---------------|--------------|
| -1 | **WIN_LOW** | < 1x | Sub-bet | — | Minimal confirmation sound |
| 0 | **WIN_EQUAL** | = 1x | Push | "PUSH" | Neutral "got your bet back" |
| 1 | **WIN_1** | 1x < w ≤ 2x | Low | "WIN" | Basic win chime |
| 2 | **WIN_2** | 2x < w ≤ 3x | Low | "WIN" | Slightly elevated |
| 3 | **WIN_3** | 3x < w ≤ 5x | Low-Medium | "NICE" | Building energy |
| 4 | **WIN_4** | 5x < w ≤ 8x | Medium | "NICE WIN" | Noticeable excitement |
| 5 | **WIN_5** | 8x < w ≤ 12x | Medium-High | "GREAT WIN" | Rising celebration |
| 6 | **WIN_6** | 12x < w ≤ 20x | High | "SUPER WIN" | Pre-big celebration |

### 9.2 Rollup Configuration per Tier

| Tier | Rollup Duration | Tick Rate | Particle Count |
|------|-----------------|-----------|----------------|
| WIN_LOW | 0ms (instant) | — | 0 |
| WIN_EQUAL | 500ms | 20/sec | 0 |
| WIN_1 | 800ms | 18/sec | 5 |
| WIN_2 | 1000ms | 16/sec | 8 |
| WIN_3 | 1200ms | 15/sec | 12 |
| WIN_4 | 1500ms | 14/sec | 18 |
| WIN_5 | 2000ms | 12/sec | 25 |
| WIN_6 | 2500ms | 10/sec | 35 |

### 9.3 Stage Names Generated

Za svaki tier generišu se sledeći stage-ovi:

```
WIN_LOW, WIN_EQUAL, WIN_1, WIN_2, WIN_3, WIN_4, WIN_5, WIN_6

WIN_PRESENT_LOW, WIN_PRESENT_EQUAL, WIN_PRESENT_1, ... WIN_PRESENT_6

ROLLUP_START_1, ROLLUP_START_2, ... ROLLUP_START_6
ROLLUP_TICK_1, ROLLUP_TICK_2, ... ROLLUP_TICK_6
ROLLUP_END_1, ROLLUP_END_2, ... ROLLUP_END_6
```

**Note:** WIN_LOW nema rollup (instant). WIN_EQUAL ima kratak rollup.

### 9.4 Default Config Code

```dart
static WinTierConfig defaultConfig() {
  return WinTierConfig(
    configId: 'default',
    name: 'Standard',
    source: WinTierConfigSource.builtin,
    tiers: [
      WinTierDefinition(
        tierId: -1,
        displayLabel: '',
        fromMultiplier: 0,
        toMultiplier: 1,
        rollupDurationMs: 0,
        rollupTickRate: 0,
        particleBurstCount: 0,
      ),
      WinTierDefinition(
        tierId: 0,
        displayLabel: 'PUSH',
        fromMultiplier: 1,
        toMultiplier: 1.001, // Effectively = 1x
        rollupDurationMs: 500,
        rollupTickRate: 20,
        particleBurstCount: 0,
      ),
      WinTierDefinition(
        tierId: 1,
        displayLabel: 'WIN',
        fromMultiplier: 1.001,
        toMultiplier: 2,
        rollupDurationMs: 800,
        rollupTickRate: 18,
        particleBurstCount: 5,
      ),
      WinTierDefinition(
        tierId: 2,
        displayLabel: 'WIN',
        fromMultiplier: 2,
        toMultiplier: 3,
        rollupDurationMs: 1000,
        rollupTickRate: 16,
        particleBurstCount: 8,
      ),
      WinTierDefinition(
        tierId: 3,
        displayLabel: 'NICE',
        fromMultiplier: 3,
        toMultiplier: 5,
        rollupDurationMs: 1200,
        rollupTickRate: 15,
        particleBurstCount: 12,
      ),
      WinTierDefinition(
        tierId: 4,
        displayLabel: 'NICE WIN',
        fromMultiplier: 5,
        toMultiplier: 8,
        rollupDurationMs: 1500,
        rollupTickRate: 14,
        particleBurstCount: 18,
      ),
      WinTierDefinition(
        tierId: 5,
        displayLabel: 'GREAT WIN',
        fromMultiplier: 8,
        toMultiplier: 12,
        rollupDurationMs: 2000,
        rollupTickRate: 12,
        particleBurstCount: 25,
      ),
      WinTierDefinition(
        tierId: 6,
        displayLabel: 'SUPER WIN',
        fromMultiplier: 12,
        toMultiplier: 20,
        rollupDurationMs: 2500,
        rollupTickRate: 10,
        particleBurstCount: 35,
      ),
      // BIG_WIN tiers start at 20x — defined in Section 10
    ],
  );
}
```

---

## 10. Big Win System (20x+)

Big Win je **JEDAN** celebration event sa **5 internih tier-ova**. Za razliku od regular win-ova gde svaki tier ima zasebne stage-ove, ovde imamo JEDAN BIG_WIN sa eskalacijom kroz tiere.

### 10.1 Industry Research Summary

Na osnovu istraživanja vodećih slot kompanija (IGT, Aristocrat, Pragmatic Play, NetEnt):

| Volatility | Big Win Threshold | Source |
|------------|-------------------|--------|
| **Low Volatility** (IGT, Everi, Bally) | **10x bet** | [Know Your Slots](https://www.knowyourslots.com/what-constitutes-a-big-win-on-slot-machines/) |
| **High Volatility** (Aristocrat, Ainsworth, WMS, Konami) | **25x bet** | [Know Your Slots](https://www.knowyourslots.com/what-constitutes-a-big-win-on-slot-machines/) |
| **YouTuber/Streamer Standard** | **100x+ bet** | Industry consensus |

**Napomena:** FluxForge koristi **20x kao početni prag** za Big Win — srednja vrednost između low i high volatility standarda.

### 10.2 Big Win Tier Ranges (Industry Standard)

| Tier | Stage Name | Opseg (× bet) | Duration | Default Label | Industry Reference |
|------|------------|---------------|----------|---------------|-------------------|
| 1 | `BIG_WIN_TIER_1` | 20x - 50x | 4s | (user-defined) | Low volatility "Big Win" |
| 2 | `BIG_WIN_TIER_2` | 50x - 100x | 4s | (user-defined) | High volatility "Mega Win" |
| 3 | `BIG_WIN_TIER_3` | 100x - 250x | 4s | (user-defined) | Streamer "Big Win" threshold |
| 4 | `BIG_WIN_TIER_4` | 250x - 500x | 4s | (user-defined) | Ultra-high win zone |
| 5 | `BIG_WIN_TIER_5` | 500x+ | 4s | (user-defined) | Max win celebration |

**Razlog za opsege:**
- **Tier 1 (20x-50x):** Većina slot igara na niskoj volatilnosti ovde ima "Big Win" celebration
- **Tier 2 (50x-100x):** High volatility igre (Aristocrat, Konami) ovde prikazuju pojačanu celebraciju
- **Tier 3 (100x+):** YouTuber/Streamer community ovo smatra pravim "Big Win" — referencirano u [Know Your Slots](https://www.knowyourslots.com/what-constitutes-a-big-win-on-slot-machines/)
- **Tier 4 (250x-500x):** Retki, značajni winovi — extra celebracija
- **Tier 5 (500x+):** Max win zona — najintenzivnija celebracija

### 10.3 Big Win Flow

```
BIG_WIN_INTRO (0.5s)
    ↓
BIG_WIN_TIER_1 (4s) ──→ Tier 1 celebration (ako win < Tier 2)
    ↓
BIG_WIN_TIER_2 (4s) ──→ Tier 2 escalation (ako win < Tier 3)
    ↓
BIG_WIN_TIER_3 (4s) ──→ Tier 3 escalation (ako win < Tier 4)
    ↓
BIG_WIN_TIER_4 (4s) ──→ Tier 4 escalation (ako win < Tier 5)
    ↓
BIG_WIN_TIER_5 (4s) ──→ Tier 5 max celebration (ako win ≥ 500x)
    ↓
BIG_WIN_END (4s)
    ↓
BIG_WIN_FADE_OUT (fade animacija)
```

**Flow Logic:**
- Win amount određuje **MAKSIMALNI** tier do kog se stiže
- Flow uvek počinje od BIG_WIN_INTRO
- Eskalira TIER po TIER do odgovarajućeg nivoa
- Preskače više tier-e ako win nije dovoljno velik
- Završava sa BIG_WIN_END i FADE_OUT

**Primer:**
- 75x win → INTRO → TIER_1 → TIER_2 → END → FADE_OUT (preskače TIER_3,4,5)
- 300x win → INTRO → TIER_1 → TIER_2 → TIER_3 → TIER_4 → END → FADE_OUT
- 1000x win → INTRO → svih 5 tier-a → END → FADE_OUT

### 10.4 Big Win Stage Names

```
BIG_WIN_INTRO      — Početak big win sekvence (0.5s)
BIG_WIN_TIER_1     — Tier 1 celebration (4s)
BIG_WIN_TIER_2     — Tier 2 escalation (4s)
BIG_WIN_TIER_3     — Tier 3 escalation (4s)
BIG_WIN_TIER_4     — Tier 4 escalation (4s)
BIG_WIN_TIER_5     — Tier 5 max celebration (4s)
BIG_WIN_END        — Završetak sa final amount (4s)
BIG_WIN_FADE_OUT   — Fade out animacija plakete
```

### 10.5 Big Win Data Model

```dart
class BigWinTierDefinition {
  /// Tier ID (1-5)
  final int tierId;

  /// Stage name: "BIG_WIN_TIER_1", etc.
  String get stageName => 'BIG_WIN_TIER_$tierId';

  /// Multiplier range
  final double fromMultiplier;  // inclusive
  final double toMultiplier;    // exclusive (Tier 5 = infinity)

  /// Display label — FULLY DYNAMIC, user-editable
  /// Default: empty string (no hardcoded names!)
  String displayLabel;

  /// Duration in milliseconds (default 4000ms)
  final int durationMs;

  /// Rollup configuration during this tier
  final int rollupTickRate;

  /// Visual intensity (1.0 - 2.0)
  final double visualIntensity;

  /// Particle effects multiplier
  final double particleMultiplier;

  /// Audio intensity (1.0 - 2.0) — volume/pitch scaling
  final double audioIntensity;
}

class BigWinConfig {
  /// Intro duration (default 500ms)
  final int introDurationMs;

  /// End duration (default 4000ms)
  final int endDurationMs;

  /// Fade out duration (default 1000ms)
  final int fadeOutDurationMs;

  /// Tier definitions (ordered 1-5)
  final List<BigWinTierDefinition> tiers;

  /// Get max tier for win amount
  int getMaxTierForWin(double winAmount, double betAmount) {
    final multiplier = betAmount > 0 ? winAmount / betAmount : 0;
    for (int i = tiers.length - 1; i >= 0; i--) {
      if (multiplier >= tiers[i].fromMultiplier) {
        return tiers[i].tierId;
      }
    }
    return 0; // Not a big win
  }

  /// Check if win qualifies for Big Win
  bool isBigWin(double winAmount, double betAmount) {
    final multiplier = betAmount > 0 ? winAmount / betAmount : 0;
    return multiplier >= 20.0; // Configurable threshold
  }
}
```

### 10.6 Default Big Win Config

```dart
static BigWinConfig defaultBigWinConfig() {
  return BigWinConfig(
    introDurationMs: 500,
    endDurationMs: 4000,
    fadeOutDurationMs: 1000,
    tiers: [
      BigWinTierDefinition(
        tierId: 1,
        fromMultiplier: 20,
        toMultiplier: 50,
        displayLabel: '', // User fills this in
        durationMs: 4000,
        rollupTickRate: 12,
        visualIntensity: 1.0,
        particleMultiplier: 1.0,
        audioIntensity: 1.0,
      ),
      BigWinTierDefinition(
        tierId: 2,
        fromMultiplier: 50,
        toMultiplier: 100,
        displayLabel: '', // User fills this in
        durationMs: 4000,
        rollupTickRate: 10,
        visualIntensity: 1.2,
        particleMultiplier: 1.5,
        audioIntensity: 1.1,
      ),
      BigWinTierDefinition(
        tierId: 3,
        fromMultiplier: 100,
        toMultiplier: 250,
        displayLabel: '', // User fills this in
        durationMs: 4000,
        rollupTickRate: 8,
        visualIntensity: 1.4,
        particleMultiplier: 2.0,
        audioIntensity: 1.2,
      ),
      BigWinTierDefinition(
        tierId: 4,
        fromMultiplier: 250,
        toMultiplier: 500,
        displayLabel: '', // User fills this in
        durationMs: 4000,
        rollupTickRate: 6,
        visualIntensity: 1.6,
        particleMultiplier: 2.5,
        audioIntensity: 1.3,
      ),
      BigWinTierDefinition(
        tierId: 5,
        fromMultiplier: 500,
        toMultiplier: double.infinity,
        displayLabel: '', // User fills this in
        durationMs: 4000,
        rollupTickRate: 4,
        visualIntensity: 2.0,
        particleMultiplier: 3.0,
        audioIntensity: 1.5,
      ),
    ],
  );
}
```

### 10.7 Big Win UI Editor

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ BIG WIN CONFIGURATION                                        │
├─────────────────────────────────────────────────────────────┤
│ Threshold: [20] x bet                                        │
│ Intro Duration: [500] ms    End Duration: [4000] ms          │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ TIER │ RANGE     │ LABEL          │ DURATION │ [Edit]  │ │
│ ├─────────────────────────────────────────────────────────┤ │
│ │  1   │ 20x-50x   │ [___________]  │ 4000ms   │ [⚙]    │ │
│ │  2   │ 50x-100x  │ [___________]  │ 4000ms   │ [⚙]    │ │
│ │  3   │ 100x-250x │ [___________]  │ 4000ms   │ [⚙]    │ │
│ │  4   │ 250x-500x │ [___________]  │ 4000ms   │ [⚙]    │ │
│ │  5   │ 500x+     │ [___________]  │ 4000ms   │ [⚙]    │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ ⓘ Labels are fully customizable. Leave empty for no text.   │
└─────────────────────────────────────────────────────────────┘
```

**Edit Dialog (per tier):**
```
┌─────────────────────────────────────────────────────────────┐
│ EDIT TIER 3                                                  │
├─────────────────────────────────────────────────────────────┤
│ From Multiplier: [100] x bet                                 │
│ To Multiplier:   [250] x bet                                 │
│ Display Label:   [MEGA WIN!__________]                       │
│ Duration:        [4000] ms                                   │
│ Rollup Speed:    [8] ticks/sec                               │
│                                                              │
│ Visual Intensity: [═══════●═══] 1.4x                         │
│ Particle Mult:    [═══════●═══] 2.0x                         │
│ Audio Intensity:  [═══════●═══] 1.2x                         │
│                                                              │
│                              [Cancel] [Save]                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. Summary

| Aspect | Decision |
|--------|----------|
| **Regular Wins** | WIN_LOW, WIN_EQUAL, WIN_1 through WIN_6 (< 20x) |
| **Big Win** | Single BIG_WIN with 5 internal tiers (20x+) |
| **Ranges** | Configurable fromMultiplier - toMultiplier |
| **Configuration** | GDD import OR manual editing |
| **Display Labels** | Fully dynamic — user-editable, no hardcoded names |
| **Validation** | Continuous ranges, no gaps/overlaps |
| **Backward Compat** | Legacy stage name mapping |

### Industry References

| Source | Key Insight |
|--------|-------------|
| [Know Your Slots](https://www.knowyourslots.com/what-constitutes-a-big-win-on-slot-machines/) | Low volatility: 10x threshold, High volatility: 25x threshold |
| [WIN.gg](https://win.gg/how-max-win-works-online-slots/) | Max win caps typically 2,000x - 50,000x |
| [All Slot Sites](https://allslotsites.com/highest-maximum-win-slots/) | Premium slots reach 100,000x+ max wins |
| [VideoGamer](https://www.videogamer.com/news/biggest-ever-slot-wins/) | Biggest multiplier wins in slot history |

---

---

## 12. Implementation Plan

### 12.1 Phase 1: Data Models (~400 LOC)

**File:** `flutter_ui/lib/models/win_tier_config.dart`

```dart
// Regular Win Tiers
class WinTierDefinition { ... }      // ~80 LOC
class WinTierConfig { ... }          // ~120 LOC

// Big Win System
class BigWinTierDefinition { ... }   // ~60 LOC
class BigWinConfig { ... }           // ~80 LOC

// Combined Config
class SlotWinConfiguration {         // ~60 LOC
  final WinTierConfig regularWins;
  final BigWinConfig bigWins;

  WinTierDefinition? getRegularTier(double winAmount, double betAmount);
  bool isBigWin(double winAmount, double betAmount);
  int getBigWinMaxTier(double winAmount, double betAmount);
}
```

### 12.2 Phase 2: Provider Integration (~200 LOC)

**File:** `flutter_ui/lib/providers/slot_lab_project_provider.dart`

Dodati:
- `SlotWinConfiguration _winConfiguration`
- `setWinConfiguration(SlotWinConfiguration config)`
- `setWinConfigurationFromGdd(Map<String, dynamic> gddJson)`
- `addRegularWinTier(WinTierDefinition tier)`
- `updateRegularWinTier(int tierId, WinTierDefinition updated)`
- `removeRegularWinTier(int tierId)`
- `updateBigWinTier(int tierId, BigWinTierDefinition updated)`
- `getWinTierForAmount(double winAmount, double betAmount)`

### 12.3 Phase 3: Rust Engine Integration (~300 LOC)

**File:** `crates/rf-slot-lab/src/win_tiers.rs` (NEW)

```rust
pub struct WinTierConfig {
    pub tiers: Vec<WinTierDefinition>,
    pub big_win_threshold: f64,
    pub big_win_tiers: Vec<BigWinTierDefinition>,
}

impl WinTierConfig {
    pub fn get_tier_for_win(&self, win: f64, bet: f64) -> Option<&WinTierDefinition>;
    pub fn is_big_win(&self, win: f64, bet: f64) -> bool;
    pub fn get_big_win_max_tier(&self, win: f64, bet: f64) -> u8;
}
```

**File:** `crates/rf-slot-lab/src/spin.rs`

Ažurirati `generate_stages()` da koristi konfigurisane tier-ove umesto hardkodiranih.

**File:** `crates/rf-bridge/src/slot_lab_ffi.rs`

Dodati FFI funkcije:
- `slot_lab_set_win_tier_config(config_json: *const c_char)`
- `slot_lab_get_win_tier_for_amount(win: f64, bet: f64) -> i32`
- `slot_lab_is_big_win(win: f64, bet: f64) -> i32`

### 12.4 Phase 4: UI Editor (~800 LOC)

**File:** `flutter_ui/lib/widgets/slot_lab/win_tier_editor_panel.dart` (NEW)

Komponente:
- `WinTierEditorPanel` — Main panel sa dva taba (Regular / Big Win)
- `_RegularTiersList` — Lista regular tier-ova sa edit/delete
- `_BigWinTiersList` — Lista big win tier-ova sa edit
- `_TierEditDialog` — Dialog za editovanje pojedinačnog tier-a
- `_BigWinTierEditDialog` — Dialog za big win tier parametre
- `_TierRangeVisualizer` — Visual prikaz opsega (bar chart)
- `_ValidationIndicator` — Status validacije (gaps/overlaps)

### 12.5 Phase 5: GDD Import Integration (~150 LOC)

**File:** `flutter_ui/lib/services/gdd_import_service.dart`

Dodati u `GameDesignDocument`:
```dart
class GameDesignDocument {
  // Existing fields...

  // NEW
  final List<GddWinTier>? winTiers;
  final GddBigWinConfig? bigWinConfig;
}

class GddWinTier {
  final int id;
  final String label;
  final double fromMultiplier;
  final double toMultiplier;
}

class GddBigWinConfig {
  final double threshold;
  final List<GddBigWinTier> tiers;
}
```

Ažurirati `GddPreviewDialog` da prikazuje win tier preview.

### 12.6 Phase 6: Stage Generation Migration (~200 LOC)

**Files to update:**
- `flutter_ui/lib/services/event_registry.dart` — Dynamic stage resolution
- `flutter_ui/lib/services/stage_configuration_service.dart` — Register dynamic stages
- `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` — Use config for win presentation
- `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` — Use config for celebration

**Legacy Mapping:**
```dart
const _legacyStageMapping = {
  'SMALL_WIN': 'WIN_1',
  'BIG_WIN': 'WIN_PRESENT_BIG', // Maps to big win system
  'MEGA_WIN': 'BIG_WIN_TIER_2',
  'EPIC_WIN': 'BIG_WIN_TIER_3',
  'ULTRA_WIN': 'BIG_WIN_TIER_5',
  // Audio stages
  'WIN_PRESENT_SMALL': 'WIN_PRESENT_1',
  'WIN_PRESENT_BIG': 'BIG_WIN_INTRO',
  'ROLLUP_START': 'ROLLUP_START_1', // Fallback
  'ROLLUP_TICK': 'ROLLUP_TICK_1',   // Fallback
  'ROLLUP_END': 'ROLLUP_END_1',     // Fallback
};
```

### 12.7 Phase 7: Testing (~300 LOC)

**File:** `flutter_ui/test/win_tier_config_test.dart` (NEW)

Test cases:
- WinTierDefinition.matches() — boundary conditions
- WinTierConfig.validate() — gap detection, overlap detection
- WinTierConfig.getTierForWin() — correct tier selection
- BigWinConfig.getMaxTierForWin() — tier escalation logic
- SlotWinConfiguration — combined functionality
- GDD import parsing
- Legacy stage mapping

### 12.8 Implementation Order

| Phase | Description | LOC | Dependencies |
|-------|-------------|-----|--------------|
| 1 | Data Models | ~400 | None |
| 2 | Provider Integration | ~200 | Phase 1 |
| 3 | Rust Engine | ~300 | Phase 1 |
| 4 | UI Editor | ~800 | Phase 1, 2 |
| 5 | GDD Import | ~150 | Phase 1, 2 |
| 6 | Stage Migration | ~200 | Phase 1, 2, 3 |
| 7 | Testing | ~300 | All phases |
| **Total** | | **~2,350** | |

---

## 13. Stage Name Reference

### 13.1 Regular Win Stages

| Tier | Win Stage | Present Stage | Rollup Stages |
|------|-----------|---------------|---------------|
| WIN_LOW | `WIN_LOW` | `WIN_PRESENT_LOW` | — (instant) |
| WIN_EQUAL | `WIN_EQUAL` | `WIN_PRESENT_EQUAL` | `ROLLUP_START_EQUAL`, `ROLLUP_TICK_EQUAL`, `ROLLUP_END_EQUAL` |
| WIN_1 | `WIN_1` | `WIN_PRESENT_1` | `ROLLUP_START_1`, `ROLLUP_TICK_1`, `ROLLUP_END_1` |
| WIN_2 | `WIN_2` | `WIN_PRESENT_2` | `ROLLUP_START_2`, `ROLLUP_TICK_2`, `ROLLUP_END_2` |
| WIN_3 | `WIN_3` | `WIN_PRESENT_3` | `ROLLUP_START_3`, `ROLLUP_TICK_3`, `ROLLUP_END_3` |
| WIN_4 | `WIN_4` | `WIN_PRESENT_4` | `ROLLUP_START_4`, `ROLLUP_TICK_4`, `ROLLUP_END_4` |
| WIN_5 | `WIN_5` | `WIN_PRESENT_5` | `ROLLUP_START_5`, `ROLLUP_TICK_5`, `ROLLUP_END_5` |
| WIN_6 | `WIN_6` | `WIN_PRESENT_6` | `ROLLUP_START_6`, `ROLLUP_TICK_6`, `ROLLUP_END_6` |

### 13.2 Big Win Stages

| Stage | Duration | Purpose |
|-------|----------|---------|
| `BIG_WIN_INTRO` | 500ms | Intro fanfare |
| `BIG_WIN_TIER_1` | 4000ms | 20x-50x celebration |
| `BIG_WIN_TIER_2` | 4000ms | 50x-100x escalation |
| `BIG_WIN_TIER_3` | 4000ms | 100x-250x escalation |
| `BIG_WIN_TIER_4` | 4000ms | 250x-500x escalation |
| `BIG_WIN_TIER_5` | 4000ms | 500x+ max celebration |
| `BIG_WIN_END` | 4000ms | Final amount display |
| `BIG_WIN_FADE_OUT` | ~1000ms | Plaque fade animation |
| `BIG_WIN_ROLLUP_TICK` | continuous | Rollup tick during tiers |

### 13.3 Audio Event Naming Convention

Za svaki stage, audio event koristi prefix `on` + camelCase:

| Stage | Audio Event Name |
|-------|------------------|
| `WIN_1` | `onWin1` |
| `WIN_PRESENT_3` | `onWinPresent3` |
| `ROLLUP_TICK_2` | `onRollupTick2` |
| `BIG_WIN_INTRO` | `onBigWinIntro` |
| `BIG_WIN_TIER_3` | `onBigWinTier3` |
| `BIG_WIN_END` | `onBigWinEnd` |

---

## 14. Summary

| Aspect | Decision |
|--------|----------|
| **Regular Wins** | WIN_LOW, WIN_EQUAL, WIN_1 through WIN_6 (< 20x) |
| **Big Win** | Single BIG_WIN with 5 internal tiers (20x+) |
| **Ranges** | Configurable fromMultiplier - toMultiplier |
| **Configuration** | GDD import OR manual editing |
| **Display Labels** | Fully dynamic — user-editable, no hardcoded names |
| **Validation** | Continuous ranges, no gaps/overlaps |
| **Backward Compat** | Legacy stage name mapping |
| **Total Implementation** | ~2,350 LOC across 7 phases |

### Industry References

| Source | Key Insight |
|--------|-------------|
| [Know Your Slots](https://www.knowyourslots.com/what-constitutes-a-big-win-on-slot-machines/) | Low volatility: 10x threshold, High volatility: 25x threshold |
| [WIN.gg](https://win.gg/how-max-win-works-online-slots/) | Max win caps typically 2,000x - 50,000x |
| [All Slot Sites](https://allslotsites.com/highest-maximum-win-slots/) | Premium slots reach 100,000x+ max wins |
| [VideoGamer](https://www.videogamer.com/news/biggest-ever-slot-wins/) | Biggest multiplier wins in slot history |

---

**Status:** ✅ SPECIFICATION COMPLETE — Ready for implementation
